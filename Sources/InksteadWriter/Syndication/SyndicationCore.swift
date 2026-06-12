import Foundation
import WebP
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PreparedMedia: Equatable, Sendable {
    public var path: URL
    public var bytes: Data
    public var mimeType: String
    public var filename: String
    public var generated: Bool
}

public struct MediaLimit: Equatable, Sendable {
    public var maxBytes: Int
    public var maxDimension: Int?

    public init(maxBytes: Int, maxDimension: Int? = nil) {
        self.maxBytes = maxBytes
        self.maxDimension = maxDimension
    }
}

public enum SyndicationStatus: String, Equatable, Sendable {
    case published
    case failed
}

public struct SyndicationResult: Equatable, Sendable {
    public var status: SyndicationStatus
    public var fields: [String: String]

    public init(status: SyndicationStatus, fields: [String: String] = [:]) {
        self.status = status
        self.fields = fields
    }

    public static func failed(_ error: String) -> SyndicationResult {
        SyndicationResult(status: .failed, fields: ["error": error])
    }

    public func frontmatterObject() -> [String: FrontmatterValue] {
        var output = fields.mapValues { FrontmatterValue.string($0) }
        output["status"] = .string(status.rawValue)
        return output
    }
}

public enum Mime {
    public static func fromPath(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        return "application/octet-stream"
    }
}

public enum SyndicationText {
    public static func markdownToText(_ markdown: String) -> String {
        MarkdownRenderer.plainTextForSyndication(markdown)
    }

    public static func text(for post: NormalizedPost) -> String {
        if let title = post.title, !title.isEmpty {
            return "\(title)\n\(post.canonicalUrl)"
        }
        return markdownToText(post.parsed.body)
    }
}

public enum SyndicationFrontmatter {
    public static func update(markdown: String, provider: SyndicationProviderName, result: SyndicationResult) -> String {
        let parsed = FrontmatterParser.parse(markdown)
        var syndication = parsed.frontmatter["syndication"]?.object ?? [:]
        syndication[provider.rawValue] = .object(result.frontmatterObject())
        let block = FrontmatterParser.serializeYamlSubset(["syndication": .object(syndication)])
        guard let yamlRange = frontmatterRange(of: markdown) else {
            return "---\n\(block)\n---\n\n\(markdown)"
        }
        let lines = String(markdown[yamlRange]).components(separatedBy: "\n")
        let spliced = splice(block: block, into: lines)
        return String(markdown[..<yamlRange.lowerBound]) + spliced.joined(separator: "\n") + String(markdown[yamlRange.upperBound...])
    }

    private static func frontmatterRange(of markdown: String) -> Range<String.Index>? {
        let newline = markdown.hasPrefix("---\r\n") ? "\r\n" : "\n"
        guard markdown.hasPrefix("---\(newline)") else { return nil }
        let start = markdown.index(markdown.startIndex, offsetBy: 3 + newline.count)
        let marker = "\(newline)---\(newline)"
        if let close = markdown.range(of: marker, range: start..<markdown.endIndex) {
            return start..<close.lowerBound
        }
        let closeAtEnd = "\(newline)---"
        if markdown.hasSuffix(closeAtEnd), markdown.distance(from: start, to: markdown.endIndex) >= closeAtEnd.count {
            return start..<markdown.index(markdown.endIndex, offsetBy: -closeAtEnd.count)
        }
        return nil
    }

    private static func splice(block: String, into lines: [String]) -> [String] {
        let blockLines = block.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: isTopLevelSyndicationKey) else {
            return lines + blockLines
        }
        var last = start
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }
            guard let first = line.first, first == " " || first == "\t" else { break }
            last = index
            index += 1
        }
        return Array(lines[..<start]) + blockLines + Array(lines[(last + 1)...])
    }

    private static func isTopLevelSyndicationKey(_ line: String) -> Bool {
        guard let first = line.first, first != " ", first != "\t" else { return false }
        return line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("syndication:")
    }
}

public enum SyndicationMedia {
    public static func prepareImage(source: URL, limit: MediaLimit) throws -> PreparedMedia {
        let bytes = try Data(contentsOf: source)
        let mime = Mime.fromPath(source.path)
        if bytes.count <= limit.maxBytes, mime.hasPrefix("image/"), withinDimensionLimit(bytes: bytes, mimeType: mime, limit: limit) {
            return PreparedMedia(path: source, bytes: bytes, mimeType: mime, filename: source.lastPathComponent, generated: false)
        }
        if let prepared = try ImageEncoder.prepareForSyndication(source: source, limit: limit) {
            return prepared
        }
        throw InksteadWriterError.io("Could not compress \(source.lastPathComponent) below \(limit.maxBytes) bytes without an image encoder.")
    }

    static func withinDimensionLimit(bytes: Data, mimeType: String, limit: MediaLimit) -> Bool {
        guard let maxDimension = limit.maxDimension else { return true }
        guard let dimensions = dimensions(bytes: bytes, mimeType: mimeType) else { return false }
        return dimensions.width <= maxDimension && dimensions.height <= maxDimension
    }

    static func dimensions(bytes: Data, mimeType: String) -> (width: Int, height: Int)? {
        if mimeType == "image/png" { return pngDimensions(bytes) }
        if mimeType == "image/jpeg" { return jpegDimensions(bytes) }
        if mimeType == "image/webp" { return webpDimensions(bytes) }
        return nil
    }

    private static func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return nil }
        return (Int(bigEndianUInt32(data, 16)), Int(bigEndianUInt32(data, 20)))
    }

    private static func jpegDimensions(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var index = 2
        while index + 8 < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            index += 2
            while index < bytes.count, bytes[index] == 0xFF { index += 1 }
            if marker == 0xD9 || marker == 0xDA { return nil }
            guard index + 2 <= bytes.count else { return nil }
            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            guard length >= 2, index + length <= bytes.count else { return nil }
            if [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].contains(marker), index + 7 < bytes.count {
                let height = Int(bytes[index + 3]) << 8 | Int(bytes[index + 4])
                let width = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                return (width, height)
            }
            index += length
        }
        return nil
    }

    private static func webpDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let image = try? WebP.decode([UInt8](data)) else { return nil }
        return (image.width, image.height)
    }

    private static func bigEndianUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}

public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var body: Data
    public var headers: [String: String]

    public init(statusCode: Int, body: Data = Data(), headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

public typealias HTTPClient = (URLRequest) async throws -> HTTPResponse

public enum DefaultHTTPClient {
    public static let requestTimeout: TimeInterval = 60
    static let maxRetries = 2

    public static func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await send(request, transport: transport) { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    static func send(
        _ request: URLRequest,
        transport: (URLRequest) async throws -> HTTPResponse,
        sleep: (TimeInterval) async throws -> Void
    ) async throws -> HTTPResponse {
        var request = request
        request.timeoutInterval = requestTimeout
        var retries = 0
        while true {
            let response = try await transport(request)
            guard response.statusCode == 429, retries < maxRetries else { return response }
            retries += 1
            try await sleep(min(retryAfterSeconds(response) ?? 1, 60))
        }
    }

    static func retryAfterSeconds(_ response: HTTPResponse) -> TimeInterval? {
        guard let raw = response.headers.first(where: { $0.key.lowercased() == "retry-after" })?.value else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }

    private static func transport(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        return HTTPResponse(statusCode: status, body: data, headers: headers(from: httpResponse))
    }

    private static func headers(from response: HTTPURLResponse?) -> [String: String] {
        var output: [String: String] = [:]
        for (field, value) in response?.allHeaderFields ?? [:] {
            output[String(describing: field)] = String(describing: value)
        }
        return output
    }
}
