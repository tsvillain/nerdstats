@testable import NerdStatsCore
import XCTest

final class ProcessControlTests: XCTestCase {
    private let user: uid_t = 501

    private func permission(pid: Int32 = 4242, name: String = "Safari", owner: uid_t?,
                            current: uid_t = 501, own: Int32 = 1000) -> ProcessStopPermission {
        ProcessControl.permission(pid: pid, name: name, ownerUID: owner, currentUID: current, ownPID: own)
    }

    func testOnlyTheCurrentUsersProcessesAreAllowed() {
        XCTAssertEqual(permission(owner: user), .allowed)
        XCTAssertEqual(permission(owner: 0), .protectedSystem)
        XCTAssertEqual(permission(owner: 88), .protectedSystem)
        XCTAssertEqual(permission(owner: nil), .protectedSystem)
    }

    func testKernelLaunchdAndRootSessionsAreProtected() {
        XCTAssertEqual(permission(pid: 0, owner: user), .protectedSystem)
        XCTAssertEqual(permission(pid: 1, owner: user), .protectedSystem)
        XCTAssertEqual(permission(owner: 0, current: 0), .protectedSystem)
    }

    func testNerdStatsItselfIsNeverOffered() {
        XCTAssertEqual(permission(pid: 1000, owner: user, own: 1000), .isNerdStats)
        XCTAssertFalse(ProcessStopPermission.isNerdStats.isAllowed)
        XCTAssertNotNil(ProcessStopPermission.isNerdStats.reason)
    }

    func testSessionCriticalProcessesAreProtected() {
        XCTAssertEqual(permission(name: "loginwindow", owner: user), .protectedSession)
    }

    func testSignals() {
        XCTAssertEqual(ProcessStopAction.quit.signal, SIGTERM)
        XCTAssertEqual(ProcessStopAction.forceQuit.signal, SIGKILL)
    }

    func testErrnoMapping() {
        XCTAssertEqual(ProcessStopError.fromErrno(ESRCH), .notRunning)
        XCTAssertEqual(ProcessStopError.fromErrno(EPERM), .notPermitted)
        XCTAssertEqual(ProcessStopError.fromErrno(EINVAL), .failed(errno: EINVAL))
        XCTAssertFalse(ProcessStopError.failed(errno: EINVAL).message.isEmpty)
    }

    func testRefusesToStopItself() throws {
        let pid = getpid()
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: pid))
        let own = ProcessUsage(pid: pid, name: "NerdStats", cpu: 0, memoryBytes: 0,
                               ownerUID: identity.ownerUID, startTime: identity.startTime)
        XCTAssertEqual(ProcessControl.permission(for: own), .isNerdStats)
        for action in ProcessStopAction.allCases {
            XCTAssertEqual(ProcessControl.stop(own, action: action), .protected(.isNerdStats))
        }
    }

    func testStopsOwnChildProcess() throws {
        for (action, signal) in [(ProcessStopAction.quit, SIGTERM), (.forceQuit, SIGKILL)] {
            let child = try launchSleep()
            let usage = try usage(of: child)
            XCTAssertEqual(ProcessControl.permission(for: usage), .allowed)
            XCTAssertNil(ProcessControl.stop(usage, action: action))
            child.waitUntilExit()
            XCTAssertEqual(child.terminationReason, .uncaughtSignal)
            XCTAssertEqual(child.terminationStatus, signal)
            // Once it has exited and been reaped, stopping it again reports that it is gone.
            XCTAssertEqual(ProcessControl.stop(usage, action: action), .notRunning)
        }
    }

    func testDoesNotSignalAReusedPID() throws {
        let child = try launchSleep()
        defer { child.terminate(); child.waitUntilExit() }
        var usage = try usage(of: child)
        usage.startTime = (usage.startTime ?? 0) &- 1
        XCTAssertEqual(ProcessControl.stop(usage, action: .forceQuit), .notRunning)
        XCTAssertTrue(child.isRunning)

        usage.startTime = nil
        XCTAssertEqual(ProcessControl.stop(usage, action: .forceQuit), .notRunning)
        XCTAssertTrue(child.isRunning)
    }

    private func launchSleep() throws -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        return child
    }

    private func usage(of child: Process) throws -> ProcessUsage {
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        XCTAssertEqual(identity.ownerUID, getuid())
        return ProcessUsage(pid: child.processIdentifier, name: "sleep", cpu: 0, memoryBytes: 0,
                            ownerUID: identity.ownerUID, startTime: identity.startTime)
    }
}
