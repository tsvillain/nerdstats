#ifndef NERDSTATS_PRIVATE_H
#define NERDSTATS_PRIVATE_H

#include <CoreFoundation/CoreFoundation.h>
#include <MacTypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// MARK: - IOHIDEventSystemClient (private)
//
// Apple Silicon Macs expose most temperature sensors as HID services rather than SMC
// keys. These functions are exported by IOKit.framework but are not in the public SDK
// headers, so they are declared here. They are used by many open-source monitors
// (e.g. Stats, iStatistica, powermetrics-style tools) and have been stable for years.

CF_IMPLICIT_BRIDGING_ENABLED
CF_ASSUME_NONNULL_BEGIN

// Declaring the opaque types as bridged CF types lets Swift manage their retain counts
// automatically under the usual Create/Copy rule.
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
CFArrayRef _Nullable IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

CF_ASSUME_NONNULL_END
CF_IMPLICIT_BRIDGING_DISABLED

/// HID usage page / usage that identify temperature sensor services.
static const int kNerdStatsHIDPageAppleVendor = 0xff00;
static const int kNerdStatsHIDUsageTemperatureSensor = 5;
/// kIOHIDEventTypeTemperature and its level field (type << 16).
static const int64_t kNerdStatsHIDEventTypeTemperature = 15;
static const int32_t kNerdStatsHIDEventFieldTemperatureLevel = 15 << 16;

// MARK: - AppleSMC user client
//
// The System Management Controller is read through the AppleSMC IOKit service using
// IOConnectCallStructMethod with this 80-byte struct for both input and output. The
// layout mirrors the kernel's definition (as used by smcFanControl and others).

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    UInt16 release;
} NSSMCVersion;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} NSSMCPLimitData;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} NSSMCKeyInfo;

typedef struct {
    UInt32 key;
    NSSMCVersion vers;
    NSSMCPLimitData pLimitData;
    NSSMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    unsigned char bytes[32];
} NSSMCParamStruct;

/// Selector for IOConnectCallStructMethod on the AppleSMC user client.
static const uint32_t kNerdStatsSMCHandleYPCEvent = 2;
/// Commands placed in NSSMCParamStruct.data8.
static const char kNerdStatsSMCCommandReadBytes = 5;
static const char kNerdStatsSMCCommandReadKeyInfo = 9;

// MARK: - NetworkStatistics (private framework)
//
// Per-socket byte counters come from NetworkStatistics.framework, the private framework
// behind `nettop`. It reads the kernel's network statistics without root. The framework
// is loaded at runtime with dlopen, so a macOS release without it simply has no
// per-connection throughput. The block-based API is wrapped in C here (NerdStatsPrivate.c).

typedef struct NerdStatsTrafficMonitor NerdStatsTrafficMonitor;

/// Called once per live TCP/UDP socket. Addresses are raw `sockaddr` bytes and may be NULL.
typedef void (*NerdStatsTrafficVisitor)(void *_Nullable context, uint64_t sourceID, int32_t pid, bool isTCP,
                                        const uint8_t *_Nullable localAddress, size_t localLength,
                                        const uint8_t *_Nullable remoteAddress, size_t remoteLength,
                                        uint64_t receivedBytes, uint64_t sentBytes);

/// Starts watching every TCP and UDP socket. Returns NULL when the framework is unavailable.
NerdStatsTrafficMonitor *_Nullable NerdStatsTrafficMonitorCreate(void);
/// Stops watching and frees the monitor.
void NerdStatsTrafficMonitorDestroy(NerdStatsTrafficMonitor *_Nonnull monitor);
/// Refreshes all counters and socket addresses, waiting at most `timeoutSeconds`, then visits every known socket.
/// Returns false if the refresh did not finish in time (the visitor is still called with the
/// last known values).
bool NerdStatsTrafficMonitorQuery(NerdStatsTrafficMonitor *_Nonnull monitor, double timeoutSeconds,
                                  void *_Nullable context, NerdStatsTrafficVisitor _Nonnull visitor);

#endif
