import Foundation

public struct ImageOptimizationOptions: Equatable, Sendable {
    public var enabled: Bool
    public var maxWidth: Int
    public var maxHeight: Int
    public var quality: Int

    public init(enabled: Bool = true, maxWidth: Int = 2400, maxHeight: Int = 2400, quality: Int = 82) {
        self.enabled = enabled
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
    }
}

public struct ImageOptimizationSummary: Equatable, Sendable {
    public var checked: Int
    public var reusedFromCache: Int
    public var generatedCacheEntries: Int
    public var copiedWithoutOptimization: Int
    public var unchangedCopies: Int

    public init(
        checked: Int = 0,
        reusedFromCache: Int = 0,
        generatedCacheEntries: Int = 0,
        copiedWithoutOptimization: Int = 0,
        unchangedCopies: Int = 0
    ) {
        self.checked = checked
        self.reusedFromCache = reusedFromCache
        self.generatedCacheEntries = generatedCacheEntries
        self.copiedWithoutOptimization = copiedWithoutOptimization
        self.unchangedCopies = unchangedCopies
    }

    public var isEmpty: Bool {
        checked == 0
    }

    public var cacheMisses: Int {
        generatedCacheEntries
    }

    mutating func add(_ outcome: ImageOptimizationOutcome) {
        checked += 1
        switch outcome {
        case .reusedFromCache:
            reusedFromCache += 1
        case .generatedCacheEntry:
            generatedCacheEntries += 1
        case .copiedWithoutOptimization:
            copiedWithoutOptimization += 1
        case .unchangedCopy:
            unchangedCopies += 1
        }
    }

    mutating func merge(_ other: ImageOptimizationSummary) {
        checked += other.checked
        reusedFromCache += other.reusedFromCache
        generatedCacheEntries += other.generatedCacheEntries
        copiedWithoutOptimization += other.copiedWithoutOptimization
        unchangedCopies += other.unchangedCopies
    }
}

public struct ImageDimensions: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public func scaledToFit(maxWidth: Int, maxHeight: Int) -> ImageDimensions {
        let scale = min(1.0, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        return ImageDimensions(
            width: max(1, Int(Double(width) * scale)),
            height: max(1, Int(Double(height) * scale))
        )
    }
}

public enum ImageOptimizer {
    public static var isAvailable: Bool {
        true
    }

    public static func options(config: InksteadWriterConfig) -> ImageOptimizationOptions {
        ImageOptimizationOptions(
            enabled: config.media?.optimize ?? true,
            maxWidth: config.media?.maxWidth ?? 2400,
            maxHeight: config.media?.maxHeight ?? 2400,
            quality: config.media?.quality ?? 82
        )
    }

    @discardableResult
    public static func optimizeBuiltImages(
        root: URL,
        config: InksteadWriterConfig,
        cacheRoot: URL? = nil,
        log: ((String) -> Void)? = nil
    ) throws -> ImageOptimizationSummary {
        let options = options(config: config)
        guard options.enabled else { return ImageOptimizationSummary() }
        let files = imageFiles(root: root)
        guard !files.isEmpty else { return ImageOptimizationSummary() }
        let cacheRoot = cacheRoot ?? mediaCacheRoot()
        let results = try BuildConcurrency.map(files) { file in
            try optimizeImage(at: file, options: options, cacheRoot: cacheRoot)
        }
        return summarize(results, log: log)
    }

    @discardableResult
    public static func copyOptimizedMedia(
        from source: URL,
        to destination: URL,
        config: InksteadWriterConfig,
        cacheRoot: URL? = nil,
        log: ((String) -> Void)? = nil
    ) throws -> ImageOptimizationSummary {
        guard FileManager.default.fileExists(atPath: source.path) else { return ImageOptimizationSummary() }
        let options = options(config: config)
        let cacheRoot = cacheRoot ?? mediaCacheRoot()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            return try copyMediaDirectory(source, to: destination, options: options, cacheRoot: cacheRoot, log: log)
        } else if values.isRegularFile == true {
            let result = try copyMediaFile(source, to: destination, options: options, cacheRoot: cacheRoot)
            return summarize([result], log: log)
        }
        return ImageOptimizationSummary()
    }

    public static func dimensions(of url: URL, cacheRoot: URL? = nil) throws -> ImageDimensions? {
        let cacheRoot = (cacheRoot ?? mediaCacheRoot()).appendingPathComponent("dimensions-v2")
        let cacheURL = try cachedImageDimensionsURL(source: url, cacheRoot: cacheRoot)
        if let cached = try cachedImageDimensions(at: cacheURL) {
            return cached
        }
        let dimensions = try ImageEncoder.dimensions(of: url)
        if let dimensions {
            try storeImageDimensions(dimensions, at: cacheURL)
        }
        return dimensions
    }

    private static func imageFiles(root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  ImageEncoder.isSupportedImage(url) else {
                return nil
            }
            return url
        }
    }

    private static func copyMediaDirectory(
        _ source: URL,
        to destination: URL,
        options: ImageOptimizationOptions,
        cacheRoot: URL,
        log: ((String) -> Void)?
    ) throws -> ImageOptimizationSummary {
        let files = try FileTreeCopyPlan.regularFilePairs(from: source, to: destination)
        guard !files.isEmpty else { return ImageOptimizationSummary() }

        let results = try BuildConcurrency.map(files) { file in
            try copyMediaFile(file.source, to: file.target, options: options, cacheRoot: cacheRoot)
        }
        return summarize(results, log: log)
    }

    private static func summarize(
        _ results: [ImageOptimizationResult],
        log: ((String) -> Void)?
    ) -> ImageOptimizationSummary {
        var summary = ImageOptimizationSummary()
        for result in results {
            summary.add(result.outcome)
            if let warning = result.warning {
                log?(warning)
            }
        }
        return summary
    }

    private static func optimizationWarning(for source: URL) -> String {
        "Media: could not optimize \(source.path); keeping original."
    }

    private static func copyMediaFile(
        _ source: URL,
        to destination: URL,
        options: ImageOptimizationOptions,
        cacheRoot: URL
    ) throws -> ImageOptimizationResult {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard options.enabled, ImageEncoder.isSupportedImage(source) else {
            if FileManager.default.fileExists(atPath: destination.path),
               try FileTreeSupport.filesHaveSameContents(source, destination) {
                return ImageOptimizationResult(outcome: .unchangedCopy)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return ImageOptimizationResult(outcome: .copiedWithoutOptimization)
        }

        let cacheURL = try cachedOptimizedImageURL(source: source, options: options, cacheRoot: cacheRoot)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            if FileManager.default.fileExists(atPath: destination.path),
               try FileTreeSupport.filesHaveSameContents(cacheURL, destination) {
                return ImageOptimizationResult(outcome: .reusedFromCache)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: cacheURL, to: destination)
            return ImageOptimizationResult(outcome: .reusedFromCache)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let optimized = try ImageEncoder.optimizeImage(at: destination, options: options)
        try storeOptimizedImageCache(from: destination, to: cacheURL)
        return ImageOptimizationResult(
            outcome: .generatedCacheEntry,
            warning: optimized ? nil : optimizationWarning(for: source)
        )
    }

    private static func optimizeImage(at url: URL, options: ImageOptimizationOptions, cacheRoot: URL) throws -> ImageOptimizationResult {
        let cacheURL = try cachedOptimizedImageURL(source: url, options: options, cacheRoot: cacheRoot)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try replaceFile(at: url, with: cacheURL)
            return ImageOptimizationResult(outcome: .reusedFromCache)
        }

        let optimized = try ImageEncoder.optimizeImage(at: url, options: options)
        try storeOptimizedImageCache(from: url, to: cacheURL)
        return ImageOptimizationResult(
            outcome: .generatedCacheEntry,
            warning: optimized ? nil : optimizationWarning(for: url)
        )
    }

    private static func cachedOptimizedImageURL(
        source: URL,
        options: ImageOptimizationOptions,
        cacheRoot: URL
    ) throws -> URL {
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let fingerprintInput = [
            "media-v3",
            source.standardizedFileURL.path,
            String(values.fileSize ?? 0),
            try FileContentHashCache.shared.hash(of: source),
            String(options.maxWidth),
            String(options.maxHeight),
            String(options.quality),
            source.pathExtension.lowercased()
        ].joined(separator: "\n")
        let key = SHA256.hex(Data(fingerprintInput.utf8))
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        return cacheRoot
            .appendingPathComponent("v3")
            .appendingPathComponent(String(key.prefix(2)))
            .appendingPathComponent("\(key).\(ext)")
    }

    private static func cachedImageDimensionsURL(source: URL, cacheRoot: URL) throws -> URL {
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let fingerprintInput = [
            "dimensions-v2",
            source.standardizedFileURL.path,
            String(values.fileSize ?? 0),
            try FileContentHashCache.shared.hash(of: source),
            source.pathExtension.lowercased()
        ].joined(separator: "\n")
        let key = SHA256.hex(Data(fingerprintInput.utf8))
        return cacheRoot
            .appendingPathComponent(String(key.prefix(2)))
            .appendingPathComponent("\(key).txt")
    }

    private static func cachedImageDimensions(at url: URL) throws -> ImageDimensions? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let parts = try String(contentsOf: url, encoding: .utf8)
            .split(separator: " ")
            .compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return ImageDimensions(width: parts[0], height: parts[1])
    }

    private static func storeImageDimensions(_ dimensions: ImageDimensions, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(dimensions.width) \(dimensions.height)".write(to: url, atomically: true, encoding: .utf8)
    }

    private static func storeOptimizedImageCache(from source: URL, to cacheURL: URL) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        let temporary = cacheURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)-\(cacheURL.lastPathComponent)")
        try FileManager.default.copyItem(at: source, to: temporary)
        do {
            try FileManager.default.moveItem(at: temporary, to: cacheURL)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if !FileManager.default.fileExists(atPath: cacheURL.path) {
                throw error
            }
        }
    }

    private static func replaceFile(at destination: URL, with source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func mediaCacheRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        InksteadWriterReleaseResolver.cacheRoot(environment: environment).appendingPathComponent("media")
    }
}

enum ImageOptimizationOutcome: Sendable {
    case reusedFromCache
    case generatedCacheEntry
    case copiedWithoutOptimization
    case unchangedCopy
}

struct ImageOptimizationResult: Sendable {
    var outcome: ImageOptimizationOutcome
    var warning: String?

    init(outcome: ImageOptimizationOutcome, warning: String? = nil) {
        self.outcome = outcome
        self.warning = warning
    }
}
