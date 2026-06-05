import Foundation
import InksteadWriter
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@main
struct InksteadWriterCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        do {
            switch command {
            case "init":
                let initArguments = Array(arguments.dropFirst())
                if initArguments.contains("--help") || initArguments.contains("-h") {
                    print(initHelp)
                    return
                }
                let parsed = try shouldPromptInit(initArguments)
                    ? promptInit(arguments: initArguments)
                    : InitCommandParser.parse(initArguments)
                let target = URL(fileURLWithPath: parsed.directory, relativeTo: root).standardizedFileURL
                let message = try SiteInitializer.initSite(at: target, options: parsed.options)
                try InksteadWriterReleaseResolver.seedCurrentBinary(root: target, executablePath: CommandLine.arguments.first, cwd: root)
                printInitSuccess(directory: parsed.directory, options: parsed.options, fallback: message)
                if isInteractiveTerminal {
                    print()
                }
                if isInteractiveTerminal, promptYesNo("Generate AGENTS.md for AI coding agents?", defaultValue: true) {
                    try SiteInitializer.writeAgentContext(at: target)
                    print(TerminalStyle.green("Created AGENTS.md."))
                }
            case "build":
                let config = try ConfigLoader.load(root: root)
                try SiteBuilder.build(root: root, config: config, log: { print($0) })
                print(TerminalStyle.green("Built site to \(config.build?.output ?? "dist")."))
            case "cache":
                try runCache(root: root, arguments: arguments)
            case "requirements":
                print(RequirementsRenderer.render(try ConfigLoader.load(root: root)), terminator: "")
            case "doctor":
                let result = Doctor.run(root: root, config: try ConfigLoader.load(root: root))
                print(result.output, terminator: "")
                if result.issues > 0 { exit(1) }
            case "deploy":
                try await Deploy.deploySite(root: root, config: try ConfigLoader.load(root: root))
            case "dev":
                let config = try ConfigLoader.load(root: root)
                let server = DevServer(root: root, config: config, port: Int(value(after: "--port", in: arguments) ?? value(after: "-p", in: arguments) ?? "4321") ?? 4321)
                try server.start()
                print("Inkstead Writer dev server running at \(TerminalStyle.accent("http://localhost:\(server.port)"))")
                while true {
                    try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                }
            case "syndicate":
                let config = try ConfigLoader.load(root: root)
                let result = await Syndicator.syndicateSite(root: root, config: config)
                print("Syndication complete. Published: \(result.published). Failed: \(result.failed).")
            case "publish":
                let config = try ConfigLoader.load(root: root)
                _ = try await Publish.publishSite(root: root, config: config)
            case "new":
                guard arguments.dropFirst().first == "post" else {
                    fail("Usage: inkstead-writer new post --kind article|note [--title title] [--text text]")
                }
                let config = try ConfigLoader.load(root: root)
                let result = try PostCreator.create(root: root, config: config, options: try newPostOptions(arguments: arguments))
                print(TerminalStyle.green("Created \(result.relativePath)"))
            case "theme":
                try runTheme(root: root, arguments: arguments)
            case "migrate":
                try runMigration(root: root, arguments: arguments)
            case "update":
                let targetVersion = value(after: "--to", in: arguments)
                let checkOnly = arguments.contains("--check")
                let dryRun = checkOnly || arguments.contains("--dry-run")
                let result = try await SiteUpdater.update(root: root, requestedVersion: targetVersion, dryRun: dryRun)
                if !result.changed {
                    print("Inkstead Writer site is up to date at \(result.previousVersion).")
                } else if checkOnly {
                    print("Inkstead Writer site can update from \(result.previousVersion) to \(result.targetVersion).")
                    exit(1)
                } else if result.dryRun {
                    if result.delegatedToDownloadedBinary {
                        print("Would download Inkstead Writer \(result.targetVersion) and run its migrations.")
                    } else {
                        for item in result.changedFiles {
                            print("Would update \(item)")
                        }
                    }
                    print("Would update Inkstead Writer site from \(result.previousVersion) to \(result.targetVersion).")
                } else if result.delegatedToDownloadedBinary {
                    print("Updated Inkstead Writer site from \(result.previousVersion) to \(result.targetVersion).")
                } else {
                    for item in result.changedFiles {
                        print("Updated \(item)")
                    }
                    print("Updated Inkstead Writer site from \(result.previousVersion) to \(result.targetVersion).")
                }
            case "version", "--version", "-v":
                print(InksteadWriterMetadata.currentVersion)
            default:
                print(commandHelp)
            }
        } catch {
            fail(error is InksteadWriterError ? String(describing: error) : error.localizedDescription)
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(TerminalStyle.red(message))\n".utf8))
        exit(1)
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        return arguments[next]
    }
}
