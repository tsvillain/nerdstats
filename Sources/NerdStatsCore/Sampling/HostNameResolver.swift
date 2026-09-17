import Darwin
import Foundation

/// Reverse DNS lookups that never block the caller.
///
/// `cachedName(for:)` returns what is already known and starts a background lookup for
/// addresses not seen before; the name shows up on a later sample. Results, including
/// failures, are cached so each address is looked up once.
public final class HostNameResolver: @unchecked Sendable {
    private enum Entry {
        case pending
        case resolved(String?)
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var pendingCount = 0
    private let maxCacheSize: Int
    private let maxPending: Int
    private let lookups: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NerdStats.reverse-dns"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()

    public init(maxCacheSize: Int = 2_000, maxPending: Int = 64) {
        self.maxCacheSize = maxCacheSize
        self.maxPending = maxPending
    }

    public func cachedName(for address: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        switch cache[address] {
        case .resolved(let name):
            return name
        case .pending:
            return nil
        case nil:
            // Skip for now when busy; the address is requested again on the next sample.
            guard pendingCount < maxPending else { return nil }
            if cache.count >= maxCacheSize {
                cache = cache.filter { if case .pending = $0.value { return true } else { return false } }
            }
            cache[address] = .pending
            pendingCount += 1
            lookups.addOperation { [weak self] in
                let name = Self.reverseLookup(address)
                guard let self else { return }
                self.lock.lock()
                // After `cancelPending` the entry is gone and was already uncounted.
                if case .pending? = self.cache[address] { self.pendingCount -= 1 }
                self.cache[address] = .resolved(name)
                self.lock.unlock()
            }
            return nil
        }
    }

    /// Stops lookups that have not started yet, e.g. when the connection list is hidden.
    public func cancelPending() {
        lookups.cancelAllOperations()
        lock.lock()
        cache = cache.filter { if case .pending = $0.value { return false } else { return true } }
        pendingCount = 0
        lock.unlock()
    }

    private static func reverseLookup(_ address: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &host, socklen_t(host.count),
                          nil, 0, NI_NAMEREQD) == 0 else { return nil }
        let name = String(cString: host)
        return name == address ? nil : name
    }
}
