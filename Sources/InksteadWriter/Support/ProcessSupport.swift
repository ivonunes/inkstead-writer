import Foundation

struct ProcessLaunch: Equatable {
    var executableURL: URL
    var arguments: [String]
}

enum ProcessSupport {
    static func shell(_ command: String) -> ProcessLaunch {
        #if os(Windows)
        ProcessLaunch(
            executableURL: URL(fileURLWithPath: #"C:\Windows\System32\cmd.exe"#),
            arguments: ["/C", command]
        )
        #else
        ProcessLaunch(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-lc", command])
        #endif
    }

    static func command(_ command: DeployCommand) -> ProcessLaunch {
        #if os(Windows)
        ProcessLaunch(
            executableURL: URL(fileURLWithPath: #"C:\Windows\System32\cmd.exe"#),
            arguments: ["/C", commandLine([command.executable] + command.arguments)]
        )
        #else
        ProcessLaunch(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [command.executable] + command.arguments
        )
        #endif
    }

    static func configure(_ process: Process, launch: ProcessLaunch, cwd: URL, environment: [String: String]? = nil) {
        process.currentDirectoryURL = cwd
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        if let environment {
            process.environment = environment
        }
    }

    private static func commandLine(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        let special = CharacterSet.whitespaces.union(CharacterSet(charactersIn: #"&|<>()^"%!"#))
        if value.rangeOfCharacter(from: special) == nil {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
