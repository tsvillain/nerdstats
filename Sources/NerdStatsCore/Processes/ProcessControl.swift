import Darwin
import Foundation

/// How to ask a process to stop.
public enum ProcessStopAction: String, CaseIterable, Sendable, Identifiable {
    /// SIGTERM: the process may save its state and exit on its own.
    case quit
    /// SIGKILL: the process ends immediately and cannot clean up.
    case forceQuit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quit: return "Quit"
        case .forceQuit: return "Force Quit"
        }
    }

    public var signal: Int32 {
        switch self {
        case .quit: return SIGTERM
        case .forceQuit: return SIGKILL
        }
    }
}

/// Whether NerdStats offers to stop a process, and why not.
public enum ProcessStopPermission: Equatable, Sendable {
    case allowed
    /// Owned by another user (e.g. root or a system account), or the owner is unknown.
    case protectedSystem
    /// Stopping it would end the user's session, e.g. `loginwindow`.
    case protectedSession
    /// NerdStats itself; use its own Quit button instead.
    case isNerdStats

    public var isAllowed: Bool { self == .allowed }

    /// Tooltip explaining why stopping is unavailable; `nil` when it is allowed.
    public var reason: String? {
        switch self {
        case .allowed: return nil
        case .protectedSystem: return "Protected: owned by the system or another user"
        case .protectedSession: return "Protected: quitting it would end your session"
        case .isNerdStats: return "This is NerdStats; use Quit at the bottom instead"
        }
    }
}

public enum ProcessStopError: Error, Equatable, Sendable {
    /// The process exited, or its PID now belongs to a different process.
    case notRunning
    case notPermitted
    case protected(ProcessStopPermission)
    case failed(errno: Int32)

    public var message: String {
        switch self {
        case .notRunning: return "It is no longer running."
        case .notPermitted: return "macOS did not allow it."
        case let .protected(permission): return permission.reason ?? "It is protected."
        case let .failed(code): return String(cString: strerror(code))
        }
    }

    static func fromErrno(_ code: Int32) -> ProcessStopError {
        switch code {
        case ESRCH: return .notRunning
        case EPERM: return .notPermitted
        default: return .failed(errno: code)
        }
    }
}

/// Stops processes owned by the current user. Never escalates privileges.
public enum ProcessControl {
    /// Processes whose exit ends the login session.
    static let sessionCriticalNames: Set<String> = ["loginwindow"]

    public static func permission(for process: ProcessUsage) -> ProcessStopPermission {
        permission(pid: process.pid, name: process.name, ownerUID: process.ownerUID,
                   currentUID: getuid(), ownPID: getpid())
    }

    static func permission(pid: Int32, name: String, ownerUID: uid_t?,
                           currentUID: uid_t, ownPID: Int32) -> ProcessStopPermission {
        if pid == ownPID { return .isNerdStats }
        // PID 0 is the kernel and PID 1 is launchd; a UID of 0 is root.
        guard pid > 1, let ownerUID, ownerUID == currentUID, currentUID != 0 else { return .protectedSystem }
        if sessionCriticalNames.contains(name) { return .protectedSession }
        return .allowed
    }

    /// Sends `action`'s signal after confirming the PID still names the same process, so a
    /// PID reused since the list was sampled is never signalled. Returns `nil` once the signal is sent.
    public static func stop(_ process: ProcessUsage, action: ProcessStopAction) -> ProcessStopError? {
        guard let current = ProcessIdentity.read(pid: process.pid),
              current.matches(process) else {
            return .notRunning
        }
        var live = process
        live.ownerUID = current.ownerUID
        let permission = permission(for: live)
        guard permission.isAllowed else { return .protected(permission) }
        guard kill(process.pid, action.signal) == 0 else {
            return .fromErrno(errno)
        }
        return nil
    }
}

/// Who owns a process and when it started, which together with its PID identifies it.
struct ProcessIdentity: Equatable {
    var ownerUID: uid_t
    /// Microseconds since 1970.
    var startTime: UInt64

    static func read(pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessIdentity(ownerUID: info.pbi_uid,
                               startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    /// A process whose start time was never read cannot be confirmed, so it does not match.
    func matches(_ process: ProcessUsage) -> Bool {
        process.startTime == startTime
    }
}
