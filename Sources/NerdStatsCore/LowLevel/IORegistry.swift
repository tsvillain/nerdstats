import Foundation
import IOKit

/// Small helpers for walking the IOKit registry (what `ioreg` shows).
public enum IORegistry {
    /// Calls `body` for every service matching `className`, releasing each afterwards.
    public static func forEachService(matching className: String, _ body: (io_object_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    /// Returns the first service matching `className`. The caller must `IOObjectRelease` it.
    public static func firstService(matching className: String) -> io_object_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        return service == 0 ? nil : service
    }

    /// All properties of a registry entry as a Swift dictionary.
    public static func properties(of entry: io_registry_entry_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dictionary
    }

    /// A single property, searching parent entries too (e.g. a GPU's PCI device holds its model name).
    public static func property(_ key: String, of entry: io_registry_entry_t, searchParents: Bool = false) -> Any? {
        let options: IOOptionBits = searchParents ? IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents) : 0
        return IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
    }

    /// Registry strings are sometimes stored as NUL-terminated `Data`.
    public static func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let data as Data:
            let trimmed = data.prefix { $0 != 0 }
            return String(data: trimmed, encoding: .utf8)
        default:
            return nil
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Reads a registry number regardless of whether it bridged as Int, Int64 or NSNumber.
    func int64(_ key: String) -> Int64? {
        (self[key] as? NSNumber)?.int64Value
    }

    func int(_ key: String) -> Int? {
        int64(key).map { Int(truncatingIfNeeded: $0) }
    }

    func bool(_ key: String) -> Bool? {
        (self[key] as? NSNumber)?.boolValue
    }

    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}
