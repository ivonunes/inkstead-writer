import XCTest
@testable import InksteadWriter

final class ProcessSupportTests: XCTestCase {
    func testShellLaunchUsesPlatformShell() {
        let launch = ProcessSupport.shell("echo ok")
        #if os(Windows)
        XCTAssertTrue(launch.executableURL.path.lowercased().hasSuffix("cmd.exe"))
        XCTAssertEqual(launch.arguments, ["/C", "echo ok"])
        #else
        XCTAssertEqual(launch.executableURL.path, "/bin/sh")
        XCTAssertEqual(launch.arguments, ["-lc", "echo ok"])
        #endif
    }

    func testCommandLaunchDoesNotHardCodeUnixEnvOnWindows() {
        let command = DeployCommand(executable: "git", arguments: ["status", "--short"], environment: [:])
        let launch = ProcessSupport.command(command)
        #if os(Windows)
        XCTAssertTrue(launch.executableURL.path.lowercased().hasSuffix("cmd.exe"))
        XCTAssertEqual(launch.arguments.first, "/C")
        #else
        XCTAssertEqual(launch.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(launch.arguments, ["git", "status", "--short"])
        #endif
    }
}
