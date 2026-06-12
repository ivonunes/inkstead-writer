import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct InksteadWriterReleasePlatform: Equatable, Sendable {
    public var os: String
    public var arch: String

    public init(os: String, arch: String) {
        self.os = os
        self.arch = arch
    }
}

public struct UpdateResult: Equatable, Sendable {
    public var previousVersion: String
    public var targetVersion: String
    public var changedFiles: [String]
    public var delegatedToDownloadedBinary: Bool
    public var dryRun: Bool = false

    public var changed: Bool {
        previousVersion != targetVersion || !changedFiles.isEmpty || delegatedToDownloadedBinary
    }
}

public enum InksteadWriterReleaseResolver {
    public static let repository = "ivonunes/inkstead-writer"

    public static func currentPlatform() throws -> InksteadWriterReleasePlatform {
        let os: String
        #if os(macOS)
        os = "macos"
        #elseif os(Linux)
        os = "linux"
        #else
        throw InksteadWriterError.config("Inkstead Writer release downloads are only supported on macOS and Linux.")
        #endif

        let arch: String
        #if arch(x86_64)
        arch = "x86_64"
        #elseif arch(arm64)
        arch = os == "linux" ? "aarch64" : "arm64"
        #else
        throw InksteadWriterError.config("Inkstead Writer release downloads are not available for this CPU architecture.")
        #endif

        return InksteadWriterReleasePlatform(os: os, arch: arch)
    }

    public static func assetName(for platform: InksteadWriterReleasePlatform, version: String) -> String {
        "\(InksteadWriterMetadata.executableName)-v\(version)-\(platform.os)-\(platform.arch).tar.gz"
    }

    public static func releaseURL(version: String, platform: InksteadWriterReleasePlatform) throws -> URL {
        guard let url = URL(string: "https://github.com/\(repository)/releases/download/v\(version)/\(assetName(for: platform, version: version))") else {
            throw InksteadWriterError.config("Inkstead Writer release URL could not be constructed.")
        }
        return url
    }

    public static func checksumURL(version: String) throws -> URL {
        guard let url = URL(string: "https://github.com/\(repository)/releases/download/v\(version)/\(InksteadWriterMetadata.executableName)-v\(version)-SHA256SUMS") else {
            throw InksteadWriterError.config("Inkstead Writer checksum URL could not be constructed.")
        }
        return url
    }

    public static func cachedBinary(cacheRoot: URL, version: String, platform: InksteadWriterReleasePlatform) -> URL {
        cacheRoot
            .appendingPathComponent("v\(version)")
            .appendingPathComponent("\(platform.os)-\(platform.arch)")
            .appendingPathComponent(InksteadWriterMetadata.executableName)
    }

    public static func cacheRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["INKSTEAD_WRITER_CACHE_DIR"] ?? environment["INKSTEAD_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }

        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.path
        #if os(macOS)
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Caches/\(InksteadWriterMetadata.cacheDirectoryName)")
        #else
        if let xdg = environment["XDG_CACHE_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent(InksteadWriterMetadata.cacheDirectoryName)
        }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".cache/\(InksteadWriterMetadata.cacheDirectoryName)")
        #endif
    }

    public static func resolve(
        version: String,
        root: URL,
        platform: InksteadWriterReleasePlatform? = nil,
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot(),
        run: (DeployCommand, URL) throws -> Void = Deploy.runCommand
    ) throws -> URL {
        let platform = try platform ?? currentPlatform()
        let binary = cachedBinary(cacheRoot: cacheRoot, version: version, platform: platform)
        if FileManager.default.isExecutableFile(atPath: binary.path) {
            return binary
        }

        let cache = binary.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try withDownloadLock(at: cache.appendingPathExtension("lock")) {
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                return binary
            }

            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let asset = assetName(for: platform, version: version)
            let archive = cache.appendingPathComponent(asset)
            let checksums = cache.appendingPathComponent("\(InksteadWriterMetadata.executableName)-v\(version)-SHA256SUMS")
            let url = try releaseURL(version: version, platform: platform)
            let sumsURL = try checksumURL(version: version)

            try run(DeployCommand(executable: "curl", arguments: ["-fsSL", url.absoluteString, "-o", archive.path], environment: [:]), root)
            try run(DeployCommand(executable: "curl", arguments: ["-fsSL", sumsURL.absoluteString, "-o", checksums.path], environment: [:]), root)
            try verifyChecksum(for: archive, asset: asset, checksums: checksums)
            try run(DeployCommand(executable: "tar", arguments: ["-xzf", archive.path, "-C", cache.path], environment: [:]), root)
            try? FileManager.default.removeItem(at: archive)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

            guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                throw InksteadWriterError.io("Downloaded Inkstead Writer release did not contain an executable binary.")
            }
            return binary
        }
    }

    public static func seedCurrentBinary(
        root: URL,
        executablePath: String?,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot()
    ) throws {
        guard let executablePath, !executablePath.isEmpty else {
            throw InksteadWriterError.io("Could not locate the running Inkstead Writer binary.")
        }
        let executable = URL(fileURLWithPath: executablePath, relativeTo: cwd).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw InksteadWriterError.io("Could not locate the running Inkstead Writer binary at \(executable.path).")
        }
        let destination = try cachedBinary(cacheRoot: cacheRoot, version: InksteadWriterMetadata.currentVersion, platform: currentPlatform())
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: executable, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private static let downloadLockStaleAge: TimeInterval = 10 * 60

    private static func withDownloadLock<T>(at lock: URL, body: () throws -> T) throws -> T {
        var locked = false
        for attempt in 0..<120 {
            do {
                try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
                locked = true
                break
            } catch {
                if !FileManager.default.fileExists(atPath: lock.path) {
                    throw error
                }
                if downloadLockIsStale(at: lock) {
                    try? FileManager.default.removeItem(at: lock)
                    continue
                }
                if attempt == 119 {
                    throw downloadLockTimeout(at: lock)
                }
                Thread.sleep(forTimeInterval: 1)
            }
        }

        guard locked else {
            throw downloadLockTimeout(at: lock)
        }
        defer { try? FileManager.default.removeItem(at: lock) }
        return try body()
    }

    private static func downloadLockIsStale(at lock: URL) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: lock.path))?[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) > downloadLockStaleAge
    }

    private static func downloadLockTimeout(at lock: URL) -> InksteadWriterError {
        .io("Timed out waiting for another Inkstead Writer download to finish. Remove \(lock.path) if no other download is running.")
    }

    private static func verifyChecksum(for archive: URL, asset: String, checksums: URL) throws {
        let expected = try checksum(for: asset, in: checksums)
        let actual = SHA256.hex(try Data(contentsOf: archive))
        guard actual.lowercased() == expected.lowercased() else {
            throw InksteadWriterError.io("Checksum verification failed for \(asset). Expected \(expected), got \(actual).")
        }
    }

    private static func checksum(for asset: String, in checksums: URL) throws -> String {
        let contents = try String(contentsOf: checksums, encoding: .utf8)
        for line in contents.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count >= 2, parts[1] == asset {
                return parts[0]
            }
        }
        throw InksteadWriterError.io("Could not find checksum for \(asset).")
    }
}

public enum SiteUpdater {
    public static func update(
        root: URL,
        requestedVersion: String? = nil,
        dryRun: Bool = false,
        http: @escaping HTTPClient = DefaultHTTPClient.send,
        resolveBinary: (String, URL) throws -> URL = { version, root in
            try InksteadWriterReleaseResolver.resolve(version: version, root: root)
        },
        runMigrationBinary: (URL, URL) throws -> Void = SiteUpdater.runDownloadedMigration
    ) async throws -> UpdateResult {
        let config = try ConfigLoader.load(root: root)
        let previous = config.recordedVersion
        let target: String
        if let requestedVersion {
            target = requestedVersion
        } else {
            target = try await latestReleaseVersion(http: http)
        }

        guard InksteadWriterVersion(previous) <= InksteadWriterVersion(target) else {
            throw InksteadWriterError.config("This site is already on Inkstead Writer \(previous), which is newer than \(target).")
        }

        if InksteadWriterVersion(previous) == InksteadWriterVersion(target) {
            return UpdateResult(previousVersion: previous, targetVersion: target, changedFiles: [], delegatedToDownloadedBinary: false, dryRun: dryRun)
        }

        if InksteadWriterVersion(target) <= InksteadWriterVersion(InksteadWriterMetadata.currentVersion) {
            let plan = try MigrationPlanner.plan(root: root, config: config, targetVersion: target)
            if dryRun {
                return UpdateResult(previousVersion: previous, targetVersion: target, changedFiles: plannedChanges(in: plan), delegatedToDownloadedBinary: false, dryRun: true)
            }
            let changed = try MigrationPlanner.apply(plan, root: root)
            if plan.hasManualActions {
                throw InksteadWriterError.config("Manual migration steps remain. Finish them, then run ./inkstead-writer migrate again.")
            }
            return UpdateResult(previousVersion: previous, targetVersion: target, changedFiles: changed, delegatedToDownloadedBinary: false)
        }

        if dryRun {
            return UpdateResult(previousVersion: previous, targetVersion: target, changedFiles: [], delegatedToDownloadedBinary: true, dryRun: true)
        }
        let binary = try resolveBinary(target, root)
        try runMigrationBinary(binary, root)
        return UpdateResult(previousVersion: previous, targetVersion: target, changedFiles: [], delegatedToDownloadedBinary: true)
    }

    public static func latestReleaseVersion(http: @escaping HTTPClient = DefaultHTTPClient.send) async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(InksteadWriterReleaseResolver.repository)/releases/latest") else {
            throw InksteadWriterError.config("GitHub release URL could not be constructed.")
        }
        var request = URLRequest(url: url)
        request.setValue("\(InksteadWriterMetadata.executableName)/\(InksteadWriterMetadata.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let response = try await http(request)
        guard (200..<300).contains(response.statusCode) else {
            throw InksteadWriterError.io("GitHub latest release lookup returned \(response.statusCode).")
        }
        guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let tag = json["tag_name"] as? String,
              !tag.isEmpty else {
            throw InksteadWriterError.parse("GitHub latest release response did not include tag_name.")
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    public static func runDownloadedMigration(_ binary: URL, root: URL) throws {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = binary
        process.arguments = ["migrate"]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw InksteadWriterError.io("\(binary.path) migrate exited with \(process.terminationStatus).")
        }
    }

    private static func plannedChanges(in plan: MigrationPlan) -> [String] {
        plan.actions.compactMap { action in
            switch action {
            case .rename(let from, let to):
                return "\(from) -> \(to)"
            case .delete(let path):
                return path
            case .write(let path, _, _):
                return path
            case .manual:
                return nil
            }
        }
    }
}
