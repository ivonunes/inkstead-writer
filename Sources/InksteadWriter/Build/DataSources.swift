import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias SyncHTTPClient = (URLRequest) throws -> HTTPResponse

private final class SyncHTTPResultBox: @unchecked Sendable {
    var result: Result<HTTPResponse, Error>?
}

public enum DefaultSyncHTTPClient {
    public static func send(_ request: URLRequest) throws -> HTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SyncHTTPResultBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.result = .failure(error)
            } else {
                let httpResponse = response as? HTTPURLResponse
                let status = httpResponse?.statusCode ?? 0
                box.result = .success(HTTPResponse(statusCode: status, body: data ?? Data(), headers: headers(from: httpResponse)))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        guard let result = box.result else {
            throw InksteadWriterError.io("Data source request did not complete.")
        }
        return try result.get()
    }

    private static func headers(from response: HTTPURLResponse?) -> [String: String] {
        var output: [String: String] = [:]
        for (field, value) in response?.allHeaderFields ?? [:] {
            output[String(describing: field)] = String(describing: value)
        }
        return output
    }
}

public enum DataSourceLoader {
    public static func load(
        root: URL,
        config: InksteadWriterConfig,
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot(),
        http: SyncHTTPClient = DefaultSyncHTTPClient.send
    ) throws -> [String: Any] {
        var output: [String: Any] = [:]
        for name in (config.data ?? [:]).keys.sorted() {
            guard let source = config.data?[name] else { continue }
            output[name] = try loadSource(name: name, source: source, root: root, cacheRoot: cacheRoot, http: http)
        }
        return output
    }

    public static func loadAsync(
        root: URL,
        config: InksteadWriterConfig,
        cacheRoot: URL = InksteadWriterReleaseResolver.cacheRoot(),
        http: @escaping HTTPClient = DefaultHTTPClient.send
    ) async throws -> [String: Any] {
        var output: [String: Any] = [:]
        for name in (config.data ?? [:]).keys.sorted() {
            guard let source = config.data?[name] else { continue }
            output[name] = try await loadSourceAsync(name: name, source: source, root: root, cacheRoot: cacheRoot, http: http)
        }
        return output
    }

    private static func loadSource(name: String, source: DataSourceConfig, root: URL, cacheRoot: URL, http: SyncHTTPClient) throws -> Any {
        do {
            if let file = source.file?.trimmingCharacters(in: .whitespacesAndNewlines), !file.isEmpty {
                return try loadLocalJSON(file, root: root)
            }
            if let url = source.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                return try loadRemoteJSON(name: name, url: url, source: source, cacheRoot: cacheRoot, http: http)
            }
            throw InksteadWriterError.config("Data source \(name) must define exactly one of url or file.")
        } catch {
            if source.required == false { return NSNull() }
            throw error
        }
    }

    private static func loadSourceAsync(name: String, source: DataSourceConfig, root: URL, cacheRoot: URL, http: @escaping HTTPClient) async throws -> Any {
        do {
            if let file = source.file?.trimmingCharacters(in: .whitespacesAndNewlines), !file.isEmpty {
                return try loadLocalJSON(file, root: root)
            }
            if let url = source.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                return try await loadRemoteJSONAsync(name: name, url: url, source: source, cacheRoot: cacheRoot, http: http)
            }
            throw InksteadWriterError.config("Data source \(name) must define exactly one of url or file.")
        } catch {
            if source.required == false { return NSNull() }
            throw error
        }
    }

    private static func loadLocalJSON(_ file: String, root: URL) throws -> Any {
        let url = file.hasPrefix("/") ? URL(fileURLWithPath: file).standardizedFileURL : root.appendingPathComponent(file).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InksteadWriterError.io("Data source file \(file) was not found.")
        }
        return try parseJSON(try Data(contentsOf: url), source: file)
    }

    private static func loadRemoteJSON(name: String, url rawURL: String, source: DataSourceConfig, cacheRoot: URL, http: SyncHTTPClient) throws -> Any {
        let cacheURL = cacheFile(name: name, source: source, cacheRoot: cacheRoot)
        if let cached = try cachedValue(cacheURL: cacheURL, cache: source.cache, source: rawURL) {
            return cached
        }
        do {
            let response = try http(try request(name: name, rawURL: rawURL, source: source, metadata: cachedMetadata(for: cacheURL)))
            return try valueFromRemoteResponse(response, name: name, sourceURL: rawURL, cache: source.cache, cacheURL: cacheURL)
        } catch {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                return try parseJSON(try Data(contentsOf: cacheURL), source: rawURL)
            }
            throw error
        }
    }

    private static func loadRemoteJSONAsync(name: String, url rawURL: String, source: DataSourceConfig, cacheRoot: URL, http: @escaping HTTPClient) async throws -> Any {
        let cacheURL = cacheFile(name: name, source: source, cacheRoot: cacheRoot)
        if let cached = try cachedValue(cacheURL: cacheURL, cache: source.cache, source: rawURL) {
            return cached
        }
        do {
            let response = try await http(try request(name: name, rawURL: rawURL, source: source, metadata: cachedMetadata(for: cacheURL)))
            return try valueFromRemoteResponse(response, name: name, sourceURL: rawURL, cache: source.cache, cacheURL: cacheURL)
        } catch {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                return try parseJSON(try Data(contentsOf: cacheURL), source: rawURL)
            }
            throw error
        }
    }

    private static func request(name: String, rawURL: String, source: DataSourceConfig, metadata: DataSourceCacheMetadata? = nil) throws -> URLRequest {
        guard let url = URL(string: rawURL) else {
            throw InksteadWriterError.config("Data source \(name) has an invalid URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(InksteadWriterMetadata.executableName)/\(InksteadWriterMetadata.currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = metadata?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = metadata?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        for (field, value) in source.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private static func valueFromRemoteResponse(_ response: HTTPResponse, name: String, sourceURL: String, cache: String?, cacheURL: URL) throws -> Any {
        if response.statusCode == 304, FileManager.default.fileExists(atPath: cacheURL.path) {
            try touch(cacheURL)
            try touch(metadataFile(for: cacheURL))
            return try parseJSON(try Data(contentsOf: cacheURL), source: sourceURL)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw InksteadWriterError.io("Data source \(name) returned HTTP \(response.statusCode).")
        }
        if cache.flatMap(cacheDuration) != nil {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try response.body.write(to: cacheURL, options: .atomic)
            try storeMetadata(from: response, for: cacheURL)
        }
        return try parseJSON(response.body, source: sourceURL)
    }

    private static func cachedValue(cacheURL: URL, cache: String?, source: String) throws -> Any? {
        guard let cache, let duration = cacheDuration(cache), cacheIsFresh(cacheURL, duration: duration) else {
            return nil
        }
        return try parseJSON(try Data(contentsOf: cacheURL), source: source)
    }

    private static func parseJSON(_ data: Data, source: String) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw InksteadWriterError.parse("Data source \(source) did not contain valid JSON.")
        }
    }

    private static func cacheFile(name: String, source: DataSourceConfig, cacheRoot: URL) -> URL {
        let fingerprintInput = [
            name,
            source.url ?? "",
            (source.headers ?? [:]).keys.sorted().map { "\($0):\(source.headers?[$0] ?? "")" }.joined(separator: "\n")
        ].joined(separator: "\n")
        let fingerprint = String(SHA256.hex(Data(fingerprintInput.utf8)).prefix(16))
        return cacheRoot
            .appendingPathComponent("data")
            .appendingPathComponent("\(name)-\(fingerprint).json")
    }

    private static func metadataFile(for cacheURL: URL) -> URL {
        cacheURL.deletingPathExtension().appendingPathExtension("metadata.json")
    }

    private static func cachedMetadata(for cacheURL: URL) -> DataSourceCacheMetadata? {
        let url = metadataFile(for: cacheURL)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(DataSourceCacheMetadata.self, from: data)
    }

    private static func storeMetadata(from response: HTTPResponse, for cacheURL: URL) throws {
        let metadata = DataSourceCacheMetadata(
            etag: response.header("ETag"),
            lastModified: response.header("Last-Modified")
        )
        guard metadata.etag != nil || metadata.lastModified != nil else { return }
        let url = metadataFile(for: cacheURL)
        try JSONEncoder().encode(metadata).write(to: url, options: .atomic)
    }

    private static func touch(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func cacheIsFresh(_ url: URL, duration: TimeInterval) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) <= duration
    }

    private static func cacheDuration(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "none" || trimmed == "false" { return nil }
        if let seconds = TimeInterval(trimmed) { return seconds }
        guard let match = trimmed.range(of: #"^\d+(?:\.\d+)?[smhd]$"#, options: .regularExpression),
              match.lowerBound == trimmed.startIndex,
              match.upperBound == trimmed.endIndex else {
            return nil
        }
        let amountText = String(trimmed.dropLast())
        guard let amount = TimeInterval(amountText), let unit = trimmed.last else { return nil }
        switch unit {
        case "s": return amount
        case "m": return amount * 60
        case "h": return amount * 60 * 60
        case "d": return amount * 60 * 60 * 24
        default: return nil
        }
    }
}

private struct DataSourceCacheMetadata: Codable {
    var etag: String?
    var lastModified: String?
}

private extension HTTPResponse {
    func header(_ name: String) -> String? {
        for (field, value) in headers where field.caseInsensitiveCompare(name) == .orderedSame {
            return value
        }
        return nil
    }
}
