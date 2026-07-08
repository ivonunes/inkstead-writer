import Foundation
import InksteadWriter
import Plume

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

extension InksteadWriterCLI {
    static func runMigration(root: URL, arguments: [String]) throws {
        let checkOnly = arguments.contains("--check")
        let dryRun = arguments.contains("--dry-run")
        let targetVersion = try value(after: "--to", in: arguments) ?? InksteadWriterMetadata.currentVersion
        let result = try MigrationRunner.run(
            root: root, targetVersion: targetVersion, checkOnly: checkOnly, dryRun: dryRun)
        if result.plan.actions.isEmpty {
            print("Inkstead Writer site is up to date.")
            return
        }
        print("Migration plan:")
        for action in result.plan.actions {
            print("  - \(action.description)")
        }
        if checkOnly {
            exit(1)
        }
        if dryRun {
            print("Dry run only; no files were changed.")
            return
        }
        for item in result.changedFiles {
            print("Updated \(item)")
        }
        if result.plan.hasManualActions {
            fail(
                "Manual migration steps remain. Finish them, then run ./inkstead-writer migrate again."
            )
        }
    }

    static func runCache(root: URL, arguments: [String]) throws {
        let subcommand = arguments.dropFirst().first ?? "list"
        let config = try ConfigLoader.loadIfPresent(root: root)
        let currentVersion = config?.recordedVersion ?? InksteadWriterMetadata.currentVersion
        let currentPlatform = try? InksteadWriterReleaseResolver.currentPlatform()
        let cacheRoot = InksteadWriterReleaseResolver.cacheRoot()

        switch subcommand {
        case "list":
            let entries = try CacheManager.list(
                cacheRoot: cacheRoot, currentVersion: currentVersion,
                currentPlatform: currentPlatform)
            if entries.isEmpty {
                print("No cached Inkstead Writer binaries in \(cacheRoot.path).")
                return
            }
            print("Cached Inkstead Writer binaries in \(cacheRoot.path):")
            for entry in entries {
                let executable = entry.isExecutable ? "" : " (not executable)"
                let current = entry.isCurrent ? " (current)" : ""
                print(
                    "  v\(entry.version) \(entry.platform) \(formatBytes(entry.sizeBytes)) \(entry.relativePath)\(current)\(executable)"
                )
            }
        case "clean":
            let result = try CacheManager.clean(
                cacheRoot: cacheRoot,
                keepVersion: currentVersion,
                version: try value(after: "--version", in: arguments),
                all: arguments.contains("--all"),
                dryRun: arguments.contains("--dry-run")
            )
            if result.removedPaths.isEmpty {
                print("No cached Inkstead Writer binaries to clean in \(cacheRoot.path).")
                return
            }
            for path in result.removedPaths {
                print("\(result.dryRun ? "Would remove" : "Removed") \(path)")
            }
            print("\(result.dryRun ? "Would free" : "Freed") \(formatBytes(result.freedBytes)).")
        default:
            fail(
                "Usage: inkstead-writer cache list | clean [--dry-run] [--all] [--version version]")
        }
    }

    static func runTheme(root: URL, arguments: [String]) throws {
        let subcommand = arguments.dropFirst().first ?? "help"
        switch subcommand {
        case "check":
            let config = try ConfigLoader.load(root: root)
            let result = try ThemeChecker.check(root: root, config: config)
            guard !result.checkedFiles.isEmpty else {
                print("No .plume templates found.")
                return
            }
            for issue in result.issues {
                let prefix = issue.severity == .warning ? "warning: " : ""
                print("\(issue.path): \(prefix)\(issue.message)")
            }
            if result.passed {
                let suffix = result.warnings.isEmpty ? "" : ", \(result.warnings.count) warnings"
                print("Theme check passed (\(result.checkedFiles.count) templates\(suffix)).")
                return
            }
            exit(1)
        case "format":
            let options = Array(arguments.dropFirst(2))
            if options.contains("--stdin") {
                print(PlumeFormatter.format(readStandardInput()), terminator: "")
            } else {
                try runThemeFormat(root: root, options: options)
            }
        case "language-server":
            PlumeLanguageServer().run()
        case "eject":
            let config = try ConfigLoader.loadIfPresent(root: root)
            let result = try ThemeEjector.eject(
                root: root, themePath: config?.theme?.path ?? "theme",
                force: arguments.contains("--force") || arguments.contains("-f"))
            for file in result.copied {
                print("Copied \(file)")
            }
            for file in result.skipped {
                print(
                    "Skipped \(file) because an equivalent template already exists. Use --force to copy anyway."
                )
            }
            if result.copied.isEmpty && result.skipped.isEmpty {
                print("No theme files were copied.")
            }
        default:
            print(
                """
                Usage:
                  inkstead-writer theme check
                  inkstead-writer theme format [--check] [--stdin] [path ...]
                  inkstead-writer theme language-server
                  inkstead-writer theme eject [--force]

                When no path is provided, theme format scans the configured theme folder.
                The language server is intended for IDE integrations.
                """)
        }
    }

    static func runThemeFormat(root: URL, options: [String]) throws {
        let checkOnly = options.contains("--check")
        let paths = options.filter { !$0.hasPrefix("-") }
        let files = try plumeFiles(root: root, paths: paths)
        guard !files.isEmpty else {
            print("No .plume templates found.")
            return
        }
        var changed: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let formatted = PlumeFormatter.format(source)
            guard formatted != source else { continue }
            changed.append(relativePath(file, root: root))
            if !checkOnly {
                try formatted.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        if changed.isEmpty {
            print("Plume templates are already formatted.")
            return
        }
        for path in changed {
            print("\(checkOnly ? "Would format" : "Formatted") \(path)")
        }
        if checkOnly { exit(1) }
    }

    static func plumeFiles(root: URL, paths: [String]) throws -> [URL] {
        let targets: [URL]
        if paths.isEmpty {
            let config = try ConfigLoader.load(root: root)
            targets = [root.appendingPathComponent(config.theme?.path ?? "theme")]
        } else {
            targets = paths.map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
        }

        var files: [URL] = []
        for target in targets {
            let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isRegularFile == true, target.pathExtension == "plume" {
                files.append(target)
            } else if values?.isDirectory == true,
                let enumerator = FileManager.default.enumerator(
                    at: target, includingPropertiesForKeys: [.isRegularFileKey])
            {
                for case let file as URL in enumerator where file.pathExtension == "plume" {
                    files.append(file)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        FileTreeSupport.relativePath(of: url, under: root) ?? url.standardizedFileURL.path
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: bytes)
    }

    static func readStandardInput() -> String {
        String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
