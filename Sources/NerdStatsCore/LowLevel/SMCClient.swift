import CNerdStatsPrivate
import Foundation
import IOKit

/// Reads values from the System Management Controller through the AppleSMC IOKit service.
///
/// Intel Macs expose temperatures and fans here. Apple Silicon Macs expose fans and a
/// few other keys; most of their temperatures come from `HIDTemperatureSensors` instead.
/// Keys that do not exist simply return `nil`.
public final class SMCClient {
    private var connection: io_connect_t = 0
    /// Key metadata (size and type) never changes, so it is looked up once per key.
    private var keyInfoCache: [UInt32: NSSMCKeyInfo] = [:]

    /// Opens a connection, or returns `nil` if the SMC is not accessible.
    public init?() {
        guard let service = IORegistry.firstService(matching: "AppleSMC") else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    /// The decoded numeric value of a four-character key such as "TC0P".
    public func read(_ key: String) -> Double? {
        guard let (type, bytes) = readRaw(key) else { return nil }
        return SMCValue.decode(type: type, bytes: bytes)
    }

    private func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        let code = SMCValue.fourCharCode(key)
        guard let info = keyInfo(code), info.dataSize > 0, info.dataSize <= 32 else { return nil }

        var input = NSSMCParamStruct()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kNerdStatsSMCCommandReadBytes
        guard let output = call(input), output.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (SMCValue.string(fromFourCharCode: info.dataType), bytes)
    }

    private func keyInfo(_ code: UInt32) -> NSSMCKeyInfo? {
        if let cached = keyInfoCache[code] { return cached }
        var input = NSSMCParamStruct()
        input.key = code
        input.data8 = kNerdStatsSMCCommandReadKeyInfo
        guard let output = call(input), output.result == 0 else { return nil }
        keyInfoCache[code] = output.keyInfo
        return output.keyInfo
    }

    /// One round trip to the SMC. Input and output share the same struct layout.
    private func call(_ input: NSSMCParamStruct) -> NSSMCParamStruct? {
        var input = input
        var output = NSSMCParamStruct()
        var outputSize = MemoryLayout<NSSMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, kNerdStatsSMCHandleYPCEvent,
            &input, MemoryLayout<NSSMCParamStruct>.stride,
            &output, &outputSize
        )
        return result == KERN_SUCCESS ? output : nil
    }
}
