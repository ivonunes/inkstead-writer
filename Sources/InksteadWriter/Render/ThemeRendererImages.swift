import Foundation
import Plume

extension ThemeRenderer {
    func plumeImageHTML(_ call: PlumeFunctionCall) throws -> PlumeSafeHTML {
        let source = stringifyPlumeValue(plumeArgument(named: "src", in: call) ?? firstPlumeArgument(call))
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InksteadWriterError.template("@image requires a source path.")
        }
        let resolved = try resolveImageReference(source, sourceName: call.context?.sourceName)
        let dimensions = try imageDimensions(for: resolved)
        let widths = responsiveWidths(from: plumeArgument(named: "widths", in: call), dimensions: dimensions)
        let srcset = try responsiveImageSrcset(for: resolved, widths: widths, dimensions: dimensions)
        var attributes: [(String, String)] = [("src", resolved.publicPath)]
        attributes.append(("alt", stringifyPlumeValue(plumeArgument(named: "alt", in: call) ?? "")))
        if !srcset.isEmpty {
            attributes.append(("srcset", srcset))
        }
        if let width = plumeArgument(named: "width", in: call).map(stringifyPlumeValue), !width.isEmpty {
            attributes.append(("width", width))
        } else if let dimensions {
            attributes.append(("width", String(dimensions.width)))
        }
        if let height = plumeArgument(named: "height", in: call).map(stringifyPlumeValue), !height.isEmpty {
            attributes.append(("height", height))
        } else if let dimensions {
            attributes.append(("height", String(dimensions.height)))
        }
        for (inputName, outputName) in [
            ("sizes", "sizes"),
            ("class", "class"),
            ("loading", "loading"),
            ("decoding", "decoding"),
            ("fetchpriority", "fetchpriority"),
            ("fetchPriority", "fetchpriority")
        ] {
            guard let value = plumeArgument(named: inputName, in: call).map(stringifyPlumeValue), !value.isEmpty else {
                continue
            }
            attributes.append((outputName, value))
        }
        if !attributes.contains(where: { $0.0 == "loading" }) {
            attributes.append(("loading", "lazy"))
        }
        if !attributes.contains(where: { $0.0 == "decoding" }) {
            attributes.append(("decoding", "async"))
        }
        let html = attributes
            .map { #"\#($0.0)="\#(escapeAttribute($0.1))""# }
            .joined(separator: " ")
        return PlumeSafeHTML("<img \(html)>")
    }

    func responsiveWidths(from value: Any?, dimensions: ImageDimensions?) -> [Int] {
        let rawValues: [Any?]
        if let values = value as? [Any?] {
            rawValues = values
        } else if let values = value as? [Any] {
            rawValues = values
        } else if let value {
            rawValues = stringifyPlumeValue(value)
                .split { $0 == "," || $0 == " " }
                .map(String.init)
        } else {
            rawValues = []
        }
        var widths = rawValues.compactMap { raw -> Int? in
            if let int = raw as? Int { return int }
            if let double = raw as? Double { return Int(double) }
            let text = stringifyPlumeValue(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(text)
        }
        widths = widths.filter { $0 > 0 }
        if let dimensions {
            widths = widths.map { min($0, dimensions.width) }
        }
        return Array(Set(widths)).sorted()
    }

    func responsiveImageSrcset(for asset: PlumeResolvedAsset, widths: [Int], dimensions: ImageDimensions?) throws -> String {
        guard !widths.isEmpty,
              let dimensions,
              case .file(let url, _) = asset.kind,
              ImageEncoder.isSupportedImage(url) else {
            return ""
        }
        var entries: [String] = []
        for width in widths {
            let height = max(1, Int((Double(dimensions.height) * Double(width) / Double(dimensions.width)).rounded()))
            let href = try emitPlumeAsset(url, variantLabel: "\(width)w", maxWidth: width, maxHeight: height)
            entries.append("\(href) \(width)w")
        }
        return entries.joined(separator: ", ")
    }

    func plumeAssetURL(_ path: String, sourceName: String?) throws -> String {
        let resolved = try resolveAssetReference(path, sourceName: sourceName)
        switch resolved.kind {
        case .external, .publicPath:
            return resolved.publicPath
        case .file(let url, let publicPath):
            if let publicPath {
                return publicPath
            }
            return try emitPlumeAsset(url)
        }
    }

    func resolveImageReference(_ path: String, sourceName: String?) throws -> PlumeResolvedAsset {
        try resolveAssetReference(path, sourceName: sourceName)
    }

    func imageDimensions(for asset: PlumeResolvedAsset) throws -> ImageDimensions? {
        guard case .file(let url, let publicPath) = asset.kind else {
            return nil
        }
        guard var dimensions = try imageDimensionCache.dimensions(for: url, load: {
            try ImageOptimizer.dimensions(of: url)
        }) else {
            return nil
        }
        if publicPath?.hasPrefix("/media/") == true {
            let options = ImageOptimizer.options(config: config)
            if options.enabled {
                dimensions = dimensions.scaledToFit(maxWidth: options.maxWidth, maxHeight: options.maxHeight)
            }
        }
        return dimensions
    }

    func resolveAssetReference(_ path: String, sourceName: String?) throws -> PlumeResolvedAsset {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InksteadWriterError.template("Plume asset path cannot be empty.")
        }
        if trimmed.range(of: #"^(https?:)?//|^(mailto|tel|data):|^#"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return PlumeResolvedAsset(publicPath: trimmed, kind: .external)
        }
        if trimmed.hasPrefix("/media/") {
            let relative = String(trimmed.dropFirst("/media/".count))
            let source = root.appendingPathComponent(config.content.media).appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw InksteadWriterError.template("Plume asset \(path) was not found.")
            }
            return PlumeResolvedAsset(publicPath: trimmed, kind: .file(source, publicPath: trimmed))
        }
        if trimmed.hasPrefix("/") {
            return PlumeResolvedAsset(publicPath: trimmed, kind: .publicPath)
        }
        let sourceURL = sourceName.flatMap { URL(fileURLWithPath: $0) }
        var candidates: [URL] = []
        if let sourceURL, sourceURL.path.hasPrefix(root.path), FileManager.default.fileExists(atPath: sourceURL.path) {
            candidates.append(sourceURL.deletingLastPathComponent().appendingPathComponent(trimmed))
        }
        candidates.append(root.appendingPathComponent(config.theme?.path ?? "theme").appendingPathComponent(trimmed))
        candidates.append(root.appendingPathComponent(trimmed))
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return PlumeResolvedAsset(publicPath: try emitPlumeAsset(candidate), kind: .file(candidate, publicPath: nil))
        }
        if let media = resolveMediaAsset(trimmed) {
            return media
        }
        throw InksteadWriterError.template("Plume asset \(path) was not found.")
    }

    func resolveMediaAsset(_ path: String) -> PlumeResolvedAsset? {
        if path.hasPrefix("\(config.content.media)/") {
            let relative = String(path.dropFirst(config.content.media.count + 1))
            let source = root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: source.path) else {
                return nil
            }
            return PlumeResolvedAsset(publicPath: "/media/\(relative)", kind: .file(source, publicPath: "/media/\(relative)"))
        }
        let source = root.appendingPathComponent(config.content.media).appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: source.path) {
            return PlumeResolvedAsset(publicPath: "/media/\(path)", kind: .file(source, publicPath: "/media/\(path)"))
        }
        return nil
    }

    func emitPlumeAsset(_ source: URL, variantLabel: String? = nil, maxWidth: Int? = nil, maxHeight: Int? = nil) throws -> String {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw InksteadWriterError.template("Plume asset \(source.path) was not found.")
        }
        let cacheKey = assetCacheKey(source, variantLabel: variantLabel, maxWidth: maxWidth, maxHeight: maxHeight)
        if let cached = emittedAssetCache.value(for: cacheKey) {
            return cached
        }
        let data = try optimizedPlumeAssetData(source, maxWidth: maxWidth, maxHeight: maxHeight)
        let hash = String(SHA256.hex(data).prefix(12))
        let ext = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension.lowercased())"
        let base = slugifyAssetName(source.deletingPathExtension().lastPathComponent, fallback: "asset")
        let suffix = variantLabel.map { "-\($0)" } ?? ""
        let fileName = "\(base)\(suffix)-\(hash)\(ext)"
        let output = dist.appendingPathComponent("assets/plume/\(fileName)")
        if !FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)
        }
        let href = "/assets/plume/\(fileName)"
        emittedAssetCache.set(href, for: cacheKey)
        return href
    }

    func assetCacheKey(_ source: URL, variantLabel: String?, maxWidth: Int?, maxHeight: Int?) -> String {
        [
            source.standardizedFileURL.path,
            variantLabel ?? "",
            maxWidth.map(String.init) ?? "",
            maxHeight.map(String.init) ?? ""
        ].joined(separator: "\u{1F}")
    }

    func optimizedPlumeAssetData(_ source: URL, maxWidth: Int? = nil, maxHeight: Int? = nil) throws -> Data {
        let options = ImageOptimizer.options(config: config)
        let shouldProcess = (options.enabled || maxWidth != nil || maxHeight != nil) && ImageEncoder.isSupportedImage(source)
        guard shouldProcess else {
            return try Data(contentsOf: source)
        }
        let cacheURL = plumeImageVariantCacheURL(
            source: source,
            contentHash: try FileContentHashCache.shared.hash(of: source),
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            options: options
        )
        if let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            return cached
        }
        let sourceData = try Data(contentsOf: source)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-plume-asset-\(UUID().uuidString).\(source.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try sourceData.write(to: temp, options: .atomic)
        try ImageEncoder.optimizeImage(at: temp, options: ImageOptimizationOptions(
            enabled: true,
            maxWidth: maxWidth ?? options.maxWidth,
            maxHeight: maxHeight ?? options.maxHeight,
            quality: options.quality
        ))
        let optimized = try Data(contentsOf: temp)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try optimized.write(to: cacheURL, options: .atomic)
        return optimized
    }

    private func plumeImageVariantCacheURL(
        source: URL,
        contentHash: String,
        maxWidth: Int?,
        maxHeight: Int?,
        options: ImageOptimizationOptions
    ) -> URL {
        let key = [
            source.standardizedFileURL.path,
            contentHash,
            maxWidth.map(String.init) ?? "",
            maxHeight.map(String.init) ?? "",
            String(options.maxWidth),
            String(options.maxHeight),
            String(options.quality),
            source.pathExtension.lowercased()
        ].joined(separator: "\u{1F}")
        let hash = SHA256.hex(Data(key.utf8))
        return InksteadWriterReleaseResolver.cacheRoot()
            .appendingPathComponent("media")
            .appendingPathComponent("plume-v1")
            .appendingPathComponent(String(hash.prefix(2)))
            .appendingPathComponent("\(hash).\(source.pathExtension.lowercased())")
    }
}
