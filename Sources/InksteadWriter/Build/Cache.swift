import Foundation

public struct CacheEntry: Equatable {
    public var version: String
    public var platform: String
    public var relativePath: String
    public var sizeBytes: Int64
    public var isExecutable: Bool
    public var isCurrent: Bool
}

public struct CacheCleanResult: Equatable {
    public var removedPaths: [String]
    public var freedBytes: Int64
    public var dryRun: Bool
}

public enum CacheManager {
    public static func list(
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot(),
        currentVersion: String? = nil,
        currentPlatform: InksteadWriterReleasePlatform? = nil
    ) throws -> [CacheEntry] {
        let cache = cacheRoot
        guard FileManager.default.fileExists(atPath: cache.path) else { return [] }
        let currentPlatformName = currentPlatform.map { "\($0.os)-\($0.arch)" }
        let versionDirectories = try childDirectories(of: cache).filter { isVersionDirectory($0) }
        var entries: [CacheEntry] = []

        for versionDirectory in versionDirectories {
            let version = normalizedVersion(fromDirectoryName: versionDirectory.lastPathComponent)
            for platformDirectory in try childDirectories(of: versionDirectory) where !platformDirectory.lastPathComponent.hasSuffix(".lock") {
                let binary = platformDirectory.appendingPathComponent(InksteadWriterMetadata.executableName)
                guard FileManager.default.fileExists(atPath: binary.path) else { continue }
                entries.append(CacheEntry(
                    version: version,
                    platform: platformDirectory.lastPathComponent,
                    relativePath: relativePath(platformDirectory, root: cache),
                    sizeBytes: try size(of: platformDirectory),
                    isExecutable: FileManager.default.isExecutableFile(atPath: binary.path),
                    isCurrent: version == currentVersion && platformDirectory.lastPathComponent == currentPlatformName
                ))
            }
        }

        return entries.sorted {
            if InksteadWriterVersion($0.version) != InksteadWriterVersion($1.version) {
                return InksteadWriterVersion($0.version) < InksteadWriterVersion($1.version)
            }
            return $0.platform < $1.platform
        }
    }

    public static func clean(
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot(),
        keepVersion: String? = nil,
        version: String? = nil,
        all: Bool = false,
        dryRun: Bool = false
    ) throws -> CacheCleanResult {
        let cache = cacheRoot
        guard FileManager.default.fileExists(atPath: cache.path) else {
            return CacheCleanResult(removedPaths: [], freedBytes: 0, dryRun: dryRun)
        }

        let candidates = try cleanCandidates(cache: cache, keepVersion: keepVersion, version: version, all: all)
        var removed: [String] = []
        var freed: Int64 = 0

        for candidate in candidates {
            freed += try size(of: candidate)
            removed.append(relativePath(candidate, root: cache))
            if !dryRun {
                try FileManager.default.removeItem(at: candidate)
            }
        }

        return CacheCleanResult(removedPaths: removed.sorted(), freedBytes: freed, dryRun: dryRun)
    }

    private static func cleanCandidates(cache: URL, keepVersion: String?, version: String?, all: Bool) throws -> [URL] {
        if all {
            return try childItems(of: cache)
        }

        if let version {
            let directory = cache.appendingPathComponent(versionDirectoryName(version))
            return FileManager.default.fileExists(atPath: directory.path) ? [directory] : []
        }

        let keep = keepVersion.map(versionDirectoryName)
        return try childDirectories(of: cache).filter { directory in
            guard isVersionDirectory(directory) else { return false }
            return directory.lastPathComponent != keep
        }
    }

    private static func childItems(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
    }

    private static func childDirectories(of directory: URL) throws -> [URL] {
        try childItems(of: directory).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func isVersionDirectory(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("v") && !url.lastPathComponent.hasSuffix(".lock")
    }

    private static func normalizedVersion(fromDirectoryName name: String) -> String {
        name.hasPrefix("v") ? String(name.dropFirst()) : name
    }

    private static func versionDirectoryName(_ version: String) -> String {
        version.hasPrefix("v") ? version : "v\(version)"
    }

    private static func size(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let itemValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard itemValues.isDirectory != true else { continue }
            total += Int64(itemValues.totalFileAllocatedSize ?? itemValues.fileSize ?? 0)
        }
        return total
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
