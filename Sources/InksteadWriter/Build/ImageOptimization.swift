import Foundation
import JPEG
import JPEGSystem
import PNG
import WebP
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

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
        cacheRoot: URL? = nil
    ) throws -> ImageOptimizationSummary {
        let options = options(config: config)
        guard options.enabled else { return ImageOptimizationSummary() }
        let files = imageFiles(root: root)
        guard !files.isEmpty else { return ImageOptimizationSummary() }
        let cacheRoot = cacheRoot ?? mediaCacheRoot()
        let workerCount = BuildConcurrency.workerCount(for: files.count)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = workerCount
        let errors = ImageOptimizationErrorBox()
        let summary = ImageOptimizationSummaryBox()

        for file in files {
            queue.addOperation {
                do {
                    summary.add(try optimizeImage(at: file, options: options, cacheRoot: cacheRoot))
                } catch {
                    errors.setIfEmpty(error)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        if let firstError = errors.firstError {
            throw firstError
        }
        return summary.value
    }

    @discardableResult
    public static func copyOptimizedMedia(
        from source: URL,
        to destination: URL,
        config: InksteadWriterConfig,
        cacheRoot: URL? = nil
    ) throws -> ImageOptimizationSummary {
        guard FileManager.default.fileExists(atPath: source.path) else { return ImageOptimizationSummary() }
        let options = options(config: config)
        let cacheRoot = cacheRoot ?? mediaCacheRoot()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            return try copyMediaDirectory(source, to: destination, options: options, cacheRoot: cacheRoot)
        } else if values.isRegularFile == true {
            var summary = ImageOptimizationSummary()
            summary.add(try copyMediaFile(source, to: destination, options: options, cacheRoot: cacheRoot))
            return summary
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
        cacheRoot: URL
    ) throws -> ImageOptimizationSummary {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else {
            return ImageOptimizationSummary()
        }
        var files: [(source: URL, target: URL)] = []
        for case let item as URL in enumerator {
            let relative = item.standardizedFileURL.path
                .replacingOccurrences(of: source.standardizedFileURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                files.append((item, target))
            }
        }
        guard !files.isEmpty else { return ImageOptimizationSummary() }

        let workerCount = BuildConcurrency.workerCount(for: files.count)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = workerCount
        let errors = ImageOptimizationErrorBox()
        let summary = ImageOptimizationSummaryBox()
        for file in files {
            queue.addOperation {
                do {
                    summary.add(try copyMediaFile(file.source, to: file.target, options: options, cacheRoot: cacheRoot))
                } catch {
                    errors.setIfEmpty(error)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        if let firstError = errors.firstError {
            throw firstError
        }
        return summary.value
    }

    private static func copyMediaFile(
        _ source: URL,
        to destination: URL,
        options: ImageOptimizationOptions,
        cacheRoot: URL
    ) throws -> ImageOptimizationOutcome {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard options.enabled, ImageEncoder.isSupportedImage(source) else {
            if FileManager.default.fileExists(atPath: destination.path),
               try filesHaveSameContents(source, destination) {
                return .unchangedCopy
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return .copiedWithoutOptimization
        }

        let cacheURL = try cachedOptimizedImageURL(source: source, options: options, cacheRoot: cacheRoot)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            if FileManager.default.fileExists(atPath: destination.path),
               try filesHaveSameContents(cacheURL, destination) {
                return .reusedFromCache
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: cacheURL, to: destination)
            return .reusedFromCache
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try ImageEncoder.optimizeImage(at: destination, options: options)
        try storeOptimizedImageCache(from: destination, to: cacheURL)
        return .generatedCacheEntry
    }

    private static func optimizeImage(at url: URL, options: ImageOptimizationOptions, cacheRoot: URL) throws -> ImageOptimizationOutcome {
        let cacheURL = try cachedOptimizedImageURL(source: url, options: options, cacheRoot: cacheRoot)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try replaceFile(at: url, with: cacheURL)
            return .reusedFromCache
        }

        try ImageEncoder.optimizeImage(at: url, options: options)
        try storeOptimizedImageCache(from: url, to: cacheURL)
        return .generatedCacheEntry
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
            try contentHash(of: source),
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
            try contentHash(of: source),
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

    private static func filesHaveSameContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rightValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard leftValues.fileSize == rightValues.fileSize else { return false }
        return try Data(contentsOf: lhs) == Data(contentsOf: rhs)
    }

    private static func contentHash(of url: URL) throws -> String {
        try SHA256.hex(Data(contentsOf: url))
    }

    private static func mediaCacheRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        InksteadWriterReleaseResolver.cacheRoot(environment: environment).appendingPathComponent("media")
    }
}

enum ImageOptimizationOutcome {
    case reusedFromCache
    case generatedCacheEntry
    case copiedWithoutOptimization
    case unchangedCopy
}

private final class ImageOptimizationErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var firstError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func setIfEmpty(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }
}

private final class ImageOptimizationSummaryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var summary = ImageOptimizationSummary()

    var value: ImageOptimizationSummary {
        lock.lock()
        defer { lock.unlock() }
        return summary
    }

    func add(_ outcome: ImageOptimizationOutcome) {
        lock.lock()
        summary.add(outcome)
        lock.unlock()
    }
}

enum ImageEncoder {
    static func isSupportedImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp"].contains(ext) {
            return true
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        return ext == "avif"
        #else
        return false
        #endif
    }

    static func optimizeImage(at url: URL, options: ImageOptimizationOptions) throws {
        let original = try Data(contentsOf: url)
        if (try? PureSwiftImageEncoder.optimizeImage(at: url, options: options)) == true {
            try keepSmallerImage(at: url, original: original)
            return
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        if let data = try PlatformImageEncoder.encodeImage(
            source: url,
            maxWidth: options.maxWidth,
            maxHeight: options.maxHeight,
            quality: Double(options.quality) / 100.0,
            forceJPEG: false
        ) {
            if data.count < original.count {
                try data.write(to: url, options: .atomic)
            }
        }
        #else
        _ = url
        _ = options
        #endif
    }

    private static func keepSmallerImage(at url: URL, original: Data) throws {
        let optimized = try Data(contentsOf: url)
        if optimized.count >= original.count {
            try original.write(to: url, options: .atomic)
        }
    }

    static func dimensions(of url: URL) throws -> ImageDimensions? {
        if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()),
           let dimensions = try? JPEGHeaderReader.dimensions(of: url) {
            return dimensions
        }
        if let dimensions = try? PureSwiftImageEncoder.dimensions(of: url) {
            return dimensions
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        return PlatformImageEncoder.dimensions(of: url)
        #else
        return nil
        #endif
    }

    static func prepareForSyndication(source: URL, limit: MediaLimit) throws -> PreparedMedia? {
        let maxDimension = limit.maxDimension ?? 4096
        for quality in [88, 82, 76, 70, 64, 58, 52, 46, 40] {
            if let data = try? PureSwiftImageEncoder.encodeJPEG(source: source, maxWidth: maxDimension, maxHeight: maxDimension, quality: quality) {
                if data.count <= limit.maxBytes {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-media-\(UUID().uuidString).jpg")
                    try data.write(to: url, options: .atomic)
                    return PreparedMedia(path: url, bytes: data, mimeType: "image/jpeg", filename: url.lastPathComponent, generated: true)
                }
            }
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        for quality in [0.88, 0.82, 0.76, 0.70, 0.64, 0.58, 0.52, 0.46, 0.40] {
            guard let data = try PlatformImageEncoder.encodeImage(source: source, maxWidth: maxDimension, maxHeight: maxDimension, quality: quality, forceJPEG: true) else {
                return nil
            }
            if data.count <= limit.maxBytes {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-media-\(UUID().uuidString).jpg")
                try data.write(to: url, options: .atomic)
                return PreparedMedia(path: url, bytes: data, mimeType: "image/jpeg", filename: url.lastPathComponent, generated: true)
            }
        }
        return nil
        #else
        _ = source
        _ = limit
        return nil
        #endif
    }
}

private struct RGBAPixel {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

private struct DecodedImage {
    var width: Int
    var height: Int
    var pixels: [RGBAPixel]

    func scaledToFit(maxWidth: Int, maxHeight: Int) -> DecodedImage {
        let scale = min(1.0, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        let outputWidth = max(1, Int(Double(width) * scale))
        let outputHeight = max(1, Int(Double(height) * scale))
        guard outputWidth != width || outputHeight != height else { return self }

        var output: [RGBAPixel] = []
        output.reserveCapacity(outputWidth * outputHeight)
        for y in 0..<outputHeight {
            let sourceY = (Double(y) + 0.5) * Double(height) / Double(outputHeight) - 0.5
            for x in 0..<outputWidth {
                let sourceX = (Double(x) + 0.5) * Double(width) / Double(outputWidth) - 0.5
                output.append(interpolatedPixel(x: sourceX, y: sourceY))
            }
        }
        return DecodedImage(width: outputWidth, height: outputHeight, pixels: output)
    }

    func oriented(_ orientation: Int?) -> DecodedImage {
        guard let orientation, orientation != 1 else { return self }
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        let outputWidth = swapsAxes ? height : width
        let outputHeight = swapsAxes ? width : height
        var output = Array(repeating: RGBAPixel(r: 0, g: 0, b: 0, a: 0), count: outputWidth * outputHeight)

        for y in 0..<height {
            for x in 0..<width {
                let destination: (x: Int, y: Int)
                switch orientation {
                case 2:
                    destination = (width - 1 - x, y)
                case 3:
                    destination = (width - 1 - x, height - 1 - y)
                case 4:
                    destination = (x, height - 1 - y)
                case 5:
                    destination = (y, x)
                case 6:
                    destination = (height - 1 - y, x)
                case 7:
                    destination = (height - 1 - y, width - 1 - x)
                case 8:
                    destination = (y, width - 1 - x)
                default:
                    destination = (x, y)
                }
                output[destination.y * outputWidth + destination.x] = pixels[y * width + x]
            }
        }
        return DecodedImage(width: outputWidth, height: outputHeight, pixels: output)
    }

    private func interpolatedPixel(x: Double, y: Double) -> RGBAPixel {
        let x0 = max(0, min(width - 1, Int(floor(x))))
        let y0 = max(0, min(height - 1, Int(floor(y))))
        let x1 = max(0, min(width - 1, x0 + 1))
        let y1 = max(0, min(height - 1, y0 + 1))
        let tx = max(0.0, min(1.0, x - Double(x0)))
        let ty = max(0.0, min(1.0, y - Double(y0)))

        let topLeft = pixels[y0 * width + x0]
        let topRight = pixels[y0 * width + x1]
        let bottomLeft = pixels[y1 * width + x0]
        let bottomRight = pixels[y1 * width + x1]

        return RGBAPixel(
            r: interpolate(topLeft.r, topRight.r, bottomLeft.r, bottomRight.r, tx: tx, ty: ty),
            g: interpolate(topLeft.g, topRight.g, bottomLeft.g, bottomRight.g, tx: tx, ty: ty),
            b: interpolate(topLeft.b, topRight.b, bottomLeft.b, bottomRight.b, tx: tx, ty: ty),
            a: interpolate(topLeft.a, topRight.a, bottomLeft.a, bottomRight.a, tx: tx, ty: ty)
        )
    }

    private func interpolate(_ topLeft: UInt8, _ topRight: UInt8, _ bottomLeft: UInt8, _ bottomRight: UInt8, tx: Double, ty: Double) -> UInt8 {
        let top = Double(topLeft) * (1.0 - tx) + Double(topRight) * tx
        let bottom = Double(bottomLeft) * (1.0 - tx) + Double(bottomRight) * tx
        return UInt8(max(0, min(255, Int((top * (1.0 - ty) + bottom * ty).rounded()))))
    }
}

private enum PureSwiftImageEncoder {
    static func optimizeImage(at url: URL, options: ImageOptimizationOptions) throws -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "jpg" || ext == "jpeg" {
            guard let data = try encodeJPEG(source: url, maxWidth: options.maxWidth, maxHeight: options.maxHeight, quality: options.quality) else {
                return false
            }
            try data.write(to: url, options: .atomic)
            return true
        }
        if ext == "png" {
            guard let data = try encodePNG(source: url, maxWidth: options.maxWidth, maxHeight: options.maxHeight) else {
                return false
            }
            try data.write(to: url, options: .atomic)
            return true
        }
        if ext == "webp" {
            guard let data = try encodeWebP(source: url, maxWidth: options.maxWidth, maxHeight: options.maxHeight, quality: options.quality) else {
                return false
            }
            try data.write(to: url, options: .atomic)
            return true
        }
        return false
    }

    static func dimensions(of url: URL) throws -> ImageDimensions? {
        let ext = url.pathExtension.lowercased()
        if ext == "jpg" || ext == "jpeg" {
            return try decodeJPEG(url).map { ImageDimensions(width: $0.width, height: $0.height) }
        }
        if ext == "png" {
            return try decodePNG(url).map { ImageDimensions(width: $0.width, height: $0.height) }
        }
        if ext == "webp" {
            return try decodeWebP(url).map { ImageDimensions(width: $0.width, height: $0.height) }
        }
        return nil
    }

    static func encodeJPEG(source: URL, maxWidth: Int, maxHeight: Int, quality: Int) throws -> Foundation.Data? {
        let ext = source.pathExtension.lowercased()
        let decoded: DecodedImage?
        if ext == "jpg" || ext == "jpeg" {
            decoded = try decodeJPEG(source)
        } else if ext == "png" {
            decoded = try decodePNG(source)
        } else if ext == "webp" {
            decoded = try decodeWebP(source)
        } else {
            return nil
        }
        guard let image = decoded?.scaledToFit(maxWidth: maxWidth, maxHeight: maxHeight) else {
            return nil
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-image-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: output) }
        try writeJPEG(image, to: output, quality: quality)
        return try Foundation.Data(contentsOf: output)
    }

    private static func encodePNG(source: URL, maxWidth: Int, maxHeight: Int) throws -> Foundation.Data? {
        guard let image = try decodePNG(source)?.scaledToFit(maxWidth: maxWidth, maxHeight: maxHeight) else {
            return nil
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try writePNG(image, to: output)
        return try Foundation.Data(contentsOf: output)
    }

    private static func encodeWebP(source: URL, maxWidth: Int, maxHeight: Int, quality: Int) throws -> Foundation.Data? {
        guard let image = try decodeWebP(source)?.scaledToFit(maxWidth: maxWidth, maxHeight: maxHeight) else {
            return nil
        }
        let pixels = image.pixels.flatMap { [$0.r, $0.g, $0.b, $0.a] }
        let webp = WebP(width: image.width, height: image.height, rgba: pixels)
        return Foundation.Data(try webp.encode(quality: Float(max(1, min(100, quality)))))
    }

    private static func decodeJPEG(_ url: URL) throws -> DecodedImage? {
        do {
            return try decodeJPEGWithoutRecovery(url)
        } catch JPEG.DecodingError.truncatedEntropyCodedSegment {
            return try decodeJPEGWithEntropyPadding(url)
        }
    }

    private static func decodeJPEGWithoutRecovery(_ url: URL) throws -> DecodedImage? {
        guard let image: JPEG.Data.Rectangular<JPEG.Common> = try .decompress(path: url.path) else {
            return nil
        }
        let pixels = image.unpack(as: JPEG.RGB.self).map { RGBAPixel(r: $0.r, g: $0.g, b: $0.b, a: 255) }
        return DecodedImage(width: image.size.x, height: image.size.y, pixels: pixels)
            .oriented(exifOrientation(from: image.metadata))
    }

    private static func decodeJPEGWithEntropyPadding(_ url: URL) throws -> DecodedImage? {
        for padByteCount in [16 * 1024, 64 * 1024, 256 * 1024] {
            guard let data = try entropyPaddedJPEGData(from: url, padByteCount: padByteCount) else {
                return nil
            }
            let padded = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-jpeg-\(UUID().uuidString).jpg")
            defer { try? FileManager.default.removeItem(at: padded) }
            try data.write(to: padded, options: .atomic)
            do {
                return try decodeJPEGWithoutRecovery(padded)
            } catch JPEG.DecodingError.truncatedEntropyCodedSegment {
                continue
            }
        }
        throw JPEG.DecodingError.truncatedEntropyCodedSegment
    }

    private static func entropyPaddedJPEGData(from url: URL, padByteCount: Int) throws -> Foundation.Data? {
        let bytes = [UInt8](try Foundation.Data(contentsOf: url))
        guard let endOfImage = terminalEndOfImageIndex(in: bytes) else {
            return nil
        }

        // Some scanners emit JPEGs that browser/libjpeg decoders recover by
        // treating premature entropy EOF as fill bits. Feed swift-jpeg the same
        // kind of stuffed fill bytes before the terminal EOI marker.
        var data = Foundation.Data()
        data.reserveCapacity(bytes.count + padByteCount)
        data.append(contentsOf: bytes[..<endOfImage])
        for _ in 0..<(padByteCount / 2) {
            data.append(0xFF)
            data.append(0x00)
        }
        data.append(contentsOf: bytes[endOfImage...])
        return data
    }

    private static func terminalEndOfImageIndex(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 2 else { return nil }
        for index in stride(from: bytes.count - 2, through: 0, by: -1) {
            if bytes[index] == 0xFF, bytes[index + 1] == 0xD9 {
                return index
            }
        }
        return nil
    }

    private static func decodePNG(_ url: URL) throws -> DecodedImage? {
        guard let image: PNG.Image = try .decompress(path: url.path) else {
            return nil
        }
        let pixels = image.unpack(as: PNG.RGBA<UInt8>.self).map { RGBAPixel(r: $0.r, g: $0.g, b: $0.b, a: $0.a) }
        return DecodedImage(width: image.size.x, height: image.size.y, pixels: pixels)
    }

    private static func decodeWebP(_ url: URL) throws -> DecodedImage? {
        let image = try WebP.decode([UInt8](Foundation.Data(contentsOf: url)))
        var pixels: [RGBAPixel] = []
        pixels.reserveCapacity(image.width * image.height)
        for index in stride(from: 0, to: image.rgba.count, by: 4) {
            pixels.append(RGBAPixel(
                r: image.rgba[index],
                g: image.rgba[index + 1],
                b: image.rgba[index + 2],
                a: image.rgba[index + 3]
            ))
        }
        return DecodedImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func writeJPEG(_ image: DecodedImage, to url: URL, quality: Int) throws {
        let pixels = image.pixels.map { pixel -> JPEG.RGB in
            let alpha = Double(pixel.a) / 255.0
            let r = UInt8((Double(pixel.r) * alpha + 255.0 * (1.0 - alpha)).rounded())
            let g = UInt8((Double(pixel.g) * alpha + 255.0 * (1.0 - alpha)).rounded())
            let b = UInt8((Double(pixel.b) * alpha + 255.0 * (1.0 - alpha)).rounded())
            return JPEG.RGB(r, g, b)
        }
        let layout: JPEG.Layout<JPEG.Common> = .init(
            format: .ycc8,
            process: .baseline,
            components: [
                1: (factor: (2, 2), qi: 0),
                2: (factor: (1, 1), qi: 1),
                3: (factor: (1, 1), qi: 1)
            ],
            scans: [
                .sequential((1, \.0, \.0), (2, \.1, \.1), (3, \.1, \.1))
            ]
        )
        let jfif: JPEG.JFIF = .init(version: .v1_2, density: (72, 72, .inches))
        let output: JPEG.Data.Rectangular<JPEG.Common> = .pack(
            size: (x: image.width, y: image.height),
            layout: layout,
            metadata: [.jfif(jfif)],
            pixels: pixels
        )
        let compression = jpegCompressionLevel(forQuality: quality)
        try output.compress(path: url.path, quanta: [
            0: JPEG.CompressionLevel.luminance(compression).quanta,
            1: JPEG.CompressionLevel.chrominance(compression).quanta
        ])
    }

    private static func writePNG(_ image: DecodedImage, to url: URL) throws {
        let pixels = image.pixels.map { PNG.RGBA<UInt8>($0.r, $0.g, $0.b, $0.a) }
        let layout = PNG.Layout(format: .rgba8(palette: [], fill: nil))
        let output = PNG.Image(
            packing: pixels,
            size: (x: image.width, y: image.height),
            layout: layout
        )
        try output.compress(path: url.path, level: 9)
    }

    private static func jpegCompressionLevel(forQuality quality: Int) -> Double {
        let clamped = max(1, min(100, quality))
        return max(0.0, min(8.0, Double(100 - clamped) / 72.0))
    }

    private static func exifOrientation(from metadata: [JPEG.Metadata]) -> Int? {
        for item in metadata {
            guard case .exif(let exif) = item,
                  let field = exif[tag: 274],
                  field.count == 1 else {
                continue
            }
            guard case .uint16 = field.type else { continue }
            switch field.box.endianness {
            case .littleEndian:
                return Int(field.box.contents.0) | Int(field.box.contents.1) << 8
            case .bigEndian:
                return Int(field.box.contents.0) << 8 | Int(field.box.contents.1)
            }
        }
        return nil
    }
}

private enum JPEGHeaderReader {
    private static let startOfImage: UInt8 = 0xD8
    private static let startOfScan: UInt8 = 0xDA
    private static let endOfImage: UInt8 = 0xD9

    private static let standaloneMarkers: Set<UInt8> = [0x01, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7]
    private static let startOfFrameMarkers: Set<UInt8> = [
        0xC0, 0xC1, 0xC2, 0xC3,
        0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB,
        0xCD, 0xCE, 0xCF
    ]

    static func dimensions(of url: URL) throws -> ImageDimensions? {
        let bytes = [UInt8](try Foundation.Data(contentsOf: url))
        guard bytes.count >= 4,
              bytes[0] == 0xFF,
              bytes[1] == startOfImage else {
            return nil
        }

        var index = 2
        var orientation: Int?
        while index < bytes.count {
            while index < bytes.count, bytes[index] == 0xFF {
                index += 1
            }
            guard index < bytes.count else { return nil }

            let marker = bytes[index]
            index += 1

            if marker == endOfImage || marker == startOfScan {
                return nil
            }
            if standaloneMarkers.contains(marker) {
                continue
            }
            guard index + 1 < bytes.count else { return nil }
            let segmentLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            guard segmentLength >= 2 else { return nil }
            let segmentStart = index + 2
            let segmentEnd = segmentStart + segmentLength - 2
            guard segmentEnd <= bytes.count else { return nil }

            if marker == 0xE1 {
                orientation = exifOrientation(in: bytes, start: segmentStart, end: segmentEnd) ?? orientation
            }

            if startOfFrameMarkers.contains(marker) {
                guard segmentStart + 5 <= segmentEnd else { return nil }
                let height = Int(bytes[segmentStart + 1]) << 8 | Int(bytes[segmentStart + 2])
                let width = Int(bytes[segmentStart + 3]) << 8 | Int(bytes[segmentStart + 4])
                guard width > 0, height > 0 else { return nil }
                if let orientation, [5, 6, 7, 8].contains(orientation) {
                    return ImageDimensions(width: height, height: width)
                }
                return ImageDimensions(width: width, height: height)
            }

            index = segmentEnd
        }
        return nil
    }

    private static func exifOrientation(in bytes: [UInt8], start: Int, end: Int) -> Int? {
        let signature = [UInt8]("Exif\0\0".utf8)
        guard end - start >= signature.count + 8,
              bytes[start..<(start + signature.count)].elementsEqual(signature) else {
            return nil
        }
        let tiffStart = start + signature.count
        let littleEndian: Bool
        if bytes[tiffStart] == 0x49, bytes[tiffStart + 1] == 0x49 {
            littleEndian = true
        } else if bytes[tiffStart] == 0x4D, bytes[tiffStart + 1] == 0x4D {
            littleEndian = false
        } else {
            return nil
        }
        guard readUInt16(bytes, at: tiffStart + 2, end: end, littleEndian: littleEndian) == 42,
              let ifdOffset = readUInt32(bytes, at: tiffStart + 4, end: end, littleEndian: littleEndian) else {
            return nil
        }
        let ifdStart = tiffStart + Int(ifdOffset)
        guard let entryCount = readUInt16(bytes, at: ifdStart, end: end, littleEndian: littleEndian) else {
            return nil
        }
        for entryIndex in 0..<Int(entryCount) {
            let entry = ifdStart + 2 + entryIndex * 12
            guard entry + 12 <= end,
                  let tag = readUInt16(bytes, at: entry, end: end, littleEndian: littleEndian),
                  let type = readUInt16(bytes, at: entry + 2, end: end, littleEndian: littleEndian),
                  let count = readUInt32(bytes, at: entry + 4, end: end, littleEndian: littleEndian),
                  tag == 0x0112,
                  type == 3,
                  count >= 1 else {
                continue
            }
            return readUInt16(bytes, at: entry + 8, end: end, littleEndian: littleEndian).map(Int.init)
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], at index: Int, end: Int, littleEndian: Bool) -> UInt16? {
        guard index >= 0, index + 1 < end else { return nil }
        if littleEndian {
            return UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        }
        return UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int, end: Int, littleEndian: Bool) -> UInt32? {
        guard index >= 0, index + 3 < end else { return nil }
        if littleEndian {
            return UInt32(bytes[index]) |
                UInt32(bytes[index + 1]) << 8 |
                UInt32(bytes[index + 2]) << 16 |
                UInt32(bytes[index + 3]) << 24
        }
        return UInt32(bytes[index]) << 24 |
            UInt32(bytes[index + 1]) << 16 |
            UInt32(bytes[index + 2]) << 8 |
            UInt32(bytes[index + 3])
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO)
private enum PlatformImageEncoder {
    static func dimensions(of url: URL) -> ImageDimensions? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return ImageDimensions(width: width, height: height)
    }

    static func encodeImage(source url: URL, maxWidth: Int, maxHeight: Int, quality: Double, forceJPEG: Bool) throws -> Foundation.Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let sourceType = CGImageSourceGetType(source) else {
            return nil
        }
        let outputType = forceJPEG ? "public.jpeg" as CFString : sourceType
        let scale = min(1.0, Double(maxWidth) / Double(image.width), Double(maxHeight) / Double(image.height))
        let outputWidth = max(1, Int(Double(image.width) * scale))
        let outputHeight = max(1, Int(Double(image.height) * scale))
        guard let rendered = render(image: image, width: outputWidth, height: outputHeight, forceOpaque: forceJPEG || outputType as String == "public.jpeg") else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, outputType, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if outputType as String == "public.jpeg" {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, quality))
        }
        CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Foundation.Data
    }

    private static func render(image: CGImage, width: Int, height: Int, forceOpaque: Bool) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = forceOpaque ? .noneSkipLast : .premultipliedLast
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        if forceOpaque {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
#endif
