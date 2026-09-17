// Most of this target only exports the declarations in include/NerdStatsPrivate.h to
// Swift. The NetworkStatistics wrapper lives here because its API is built on blocks and
// dispatch queues, which are simpler to drive from C than through dlsym in Swift.
#include "NerdStatsPrivate.h"

#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdlib.h>

typedef void *NStatManagerRef;
typedef void *NStatSourceRef;

struct NerdStatsTrafficMonitor {
    NStatManagerRef manager;
    dispatch_queue_t queue;
    /// Source ID (CFNumber) → description (process and addresses), and → latest counts
    /// (bytes). Only touched on `queue`.
    CFMutableDictionaryRef descriptions;
    CFMutableDictionaryRef counts;
    uint64_t nextSourceID;
    void (*destroyManager)(NStatManagerRef);
    int (*queryCounts)(NStatManagerRef, void (^)(void));
};

static void *NerdStatsFrameworkHandle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_LAZY);
    });
    return handle;
}

NerdStatsTrafficMonitor *NerdStatsTrafficMonitorCreate(void) {
    void *handle = NerdStatsFrameworkHandle();
    if (!handle) return NULL;

    NStatManagerRef (*create)(CFAllocatorRef, dispatch_queue_t, void (^)(NStatSourceRef, void *)) = dlsym(handle, "NStatManagerCreate");
    void (*addAllTCP)(NStatManagerRef, int, int) = dlsym(handle, "NStatManagerAddAllTCPWithFilter");
    void (*addAllUDP)(NStatManagerRef, int, int) = dlsym(handle, "NStatManagerAddAllUDPWithFilter");
    void (*setDescriptionBlock)(NStatSourceRef, void (^)(CFDictionaryRef)) = dlsym(handle, "NStatSourceSetDescriptionBlock");
    void (*setCountsBlock)(NStatSourceRef, void (^)(CFDictionaryRef)) = dlsym(handle, "NStatSourceSetCountsBlock");
    void (*queryDescription)(NStatSourceRef) = dlsym(handle, "NStatSourceQueryDescription");
    void (*setRemovedBlock)(NStatSourceRef, void (^)(void)) = dlsym(handle, "NStatSourceSetRemovedBlock");
    void (*destroyManager)(NStatManagerRef) = dlsym(handle, "NStatManagerDestroy");
    int (*queryCounts)(NStatManagerRef, void (^)(void)) = dlsym(handle, "NStatManagerQueryAllSources");
    if (!create || !addAllTCP || !addAllUDP || !setDescriptionBlock || !setCountsBlock || !queryDescription
        || !setRemovedBlock || !destroyManager || !queryCounts) {
        return NULL;
    }

    NerdStatsTrafficMonitor *monitor = calloc(1, sizeof(NerdStatsTrafficMonitor));
    if (!monitor) return NULL;
    monitor->queue = dispatch_queue_create("NerdStats.traffic", DISPATCH_QUEUE_SERIAL);
    monitor->descriptions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    monitor->counts = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    monitor->destroyManager = destroyManager;
    monitor->queryCounts = queryCounts;

    // Callbacks run on monitor->queue, so the dictionary needs no lock.
    monitor->manager = create(kCFAllocatorDefault, monitor->queue, ^(NStatSourceRef source, void *unused) {
        (void)unused;
        uint64_t identifier = ++monitor->nextSourceID;
        CFNumberRef key = CFNumberCreate(NULL, kCFNumberSInt64Type, &identifier);
        CFRetain(key); // Released by the removed block.
        setDescriptionBlock(source, ^(CFDictionaryRef description) {
            if (description) CFDictionarySetValue(monitor->descriptions, key, description);
        });
        setCountsBlock(source, ^(CFDictionaryRef counts) {
            if (counts) CFDictionarySetValue(monitor->counts, key, counts);
        });
        setRemovedBlock(source, ^{
            CFDictionaryRemoveValue(monitor->descriptions, key);
            CFDictionaryRemoveValue(monitor->counts, key);
            CFRelease(key);
        });
        CFRelease(key);
        // A socket's process and addresses never change, so its description is fetched once;
        // each query afterwards only refreshes the byte counts.
        queryDescription(source);
    });
    if (!monitor->manager) {
        CFRelease(monitor->descriptions);
        CFRelease(monitor->counts);
        dispatch_release(monitor->queue);
        free(monitor);
        return NULL;
    }
    addAllTCP(monitor->manager, 0, 0);
    addAllUDP(monitor->manager, 0, 0);
    return monitor;
}

void NerdStatsTrafficMonitorDestroy(NerdStatsTrafficMonitor *monitor) {
    monitor->destroyManager(monitor->manager);
    // Let callbacks already queued finish before freeing what they use.
    dispatch_async(monitor->queue, ^{
        CFRelease(monitor->descriptions);
        CFRelease(monitor->counts);
        dispatch_queue_t queue = monitor->queue;
        free(monitor);
        dispatch_release(queue);
    });
}

static uint64_t NerdStatsUInt64(CFDictionaryRef dictionary, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    uint64_t result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue(value, kCFNumberSInt64Type, &result);
    }
    return result;
}

static CFDataRef _Nullable NerdStatsData(CFDictionaryRef dictionary, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    return value && CFGetTypeID(value) == CFDataGetTypeID() ? value : NULL;
}

bool NerdStatsTrafficMonitorQuery(NerdStatsTrafficMonitor *monitor, double timeoutSeconds,
                                  void *context, NerdStatsTrafficVisitor visitor) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_retain(done); // Released by the completion block, which may outlive a timeout.
    monitor->queryCounts(monitor->manager, ^{
        dispatch_semaphore_signal(done);
        dispatch_release(done);
    });
    bool finished = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC))) == 0;
    dispatch_release(done);

    dispatch_sync(monitor->queue, ^{
        CFIndex count = CFDictionaryGetCount(monitor->descriptions);
        if (count == 0) return;
        CFTypeRef *keys = malloc(sizeof(CFTypeRef) * (size_t)count);
        CFTypeRef *values = malloc(sizeof(CFTypeRef) * (size_t)count);
        if (keys && values) {
            CFDictionaryGetKeysAndValues(monitor->descriptions, keys, values);
            for (CFIndex index = 0; index < count; index++) {
                CFDictionaryRef description = values[index];
                if (CFGetTypeID(description) != CFDictionaryGetTypeID()) continue;
                uint64_t identifier = 0;
                CFNumberGetValue(keys[index], kCFNumberSInt64Type, &identifier);
                CFTypeRef provider = CFDictionaryGetValue(description, CFSTR("provider"));
                bool isTCP = provider && CFGetTypeID(provider) == CFStringGetTypeID()
                    && CFStringCompare(provider, CFSTR("TCP"), 0) == kCFCompareEqualTo;
                CFDictionaryRef counts = CFDictionaryGetValue(monitor->counts, keys[index]);
                if (!counts) continue;
                CFDataRef local = NerdStatsData(description, CFSTR("localAddress"));
                CFDataRef remote = NerdStatsData(description, CFSTR("remoteAddress"));
                visitor(context, identifier, (int32_t)NerdStatsUInt64(description, CFSTR("processID")), isTCP,
                        local ? CFDataGetBytePtr(local) : NULL, local ? (size_t)CFDataGetLength(local) : 0,
                        remote ? CFDataGetBytePtr(remote) : NULL, remote ? (size_t)CFDataGetLength(remote) : 0,
                        NerdStatsUInt64(counts, CFSTR("rxBytes")), NerdStatsUInt64(counts, CFSTR("txBytes")));
            }
        }
        free(keys);
        free(values);
    });
    return finished;
}
