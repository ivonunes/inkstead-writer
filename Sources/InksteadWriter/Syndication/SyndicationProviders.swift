import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SyndicationContext {
    public var root: URL
    public var env: [String: String]
    public var http: HTTPClient
    public var now: () -> Date
    public var nonce: () -> String

    public init(
        root: URL,
        env: [String: String],
        http: @escaping HTTPClient = DefaultHTTPClient.send,
        now: @escaping () -> Date = Date.init,
        nonce: @escaping () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "") }
    ) {
        self.root = root
        self.env = env
        self.http = http
        self.now = now
        self.nonce = nonce
    }
}

public enum SyndicationProviders {
    public static func canSyndicate(_ provider: SyndicationProviderName, post: NormalizedPost) -> Bool {
        switch provider {
        case .mastodon, .bluesky:
            true
        case .flickr:
            post.kind == .photoNote
        }
    }

    public static func publish(_ provider: SyndicationProviderName, post: NormalizedPost, context: SyndicationContext) async -> SyndicationResult {
        do {
            switch provider {
            case .mastodon:
                return try await publishMastodon(post: post, context: context)
            case .bluesky:
                return try await publishBluesky(post: post, context: context)
            case .flickr:
                return try await publishFlickr(post: post, context: context)
            }
        } catch {
            return .failed(error is InksteadWriterError ? String(describing: error) : error.localizedDescription)
        }
    }

    private static func publishMastodon(post: NormalizedPost, context: SyndicationContext) async throws -> SyndicationResult {
        guard let instance = context.env["MASTODON_INSTANCE_URL"]?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !instance.isEmpty,
              let token = context.env["MASTODON_ACCESS_TOKEN"], !token.isEmpty else {
            return .failed("Missing Mastodon credentials.")
        }
        let limit = try await mastodonMediaLimit(instance: instance, context: context)
        var mediaIDs: [String] = []
        for photoPath in post.sourcePhotos {
            let prepared = try SyndicationMedia.prepareImage(source: URL(fileURLWithPath: photoPath), limit: limit)
            let boundary = "InksteadWriterBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            var form = MultipartForm(boundary: boundary)
            form.addFile(name: "file", filename: prepared.filename, mimeType: prepared.mimeType, bytes: prepared.bytes)
            if let alt = post.alt { form.addField(name: "description", value: alt) }
            var request = URLRequest(url: URL(string: "\(instance)/api/v2/media")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = form.body()
            let upload = try await context.http(request)
            guard (200..<300).contains(upload.statusCode) else {
                return .failed("Mastodon media upload returned \(upload.statusCode).")
            }
            if let json = try JSONSerialization.jsonObject(with: upload.body) as? [String: Any], let id = json["id"] as? String {
                mediaIDs.append(id)
            }
        }
        var request = URLRequest(url: URL(string: "\(instance)/api/v1/statuses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": SyndicationText.text(for: post), "media_ids": mediaIDs])
        let response = try await context.http(request)
        guard (200..<300).contains(response.statusCode) else {
            return .failed("Mastodon returned \(response.statusCode).")
        }
        let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        return SyndicationResult(status: .published, fields: [
            "id": json?["id"] as? String,
            "url": json?["url"] as? String,
            "publishedAt": ISO8601DateFormatter().string(from: context.now())
        ].compactMapValues { $0 })
    }

    private static func mastodonMediaLimit(instance: String, context: SyndicationContext) async throws -> MediaLimit {
        var request = URLRequest(url: URL(string: "\(instance)/api/v2/instance")!)
        request.httpMethod = "GET"
        let fallback = MediaLimit(maxBytes: 10 * 1024 * 1024, maxDimension: 4096)
        let response = try? await context.http(request)
        guard let response, (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let configuration = json["configuration"] as? [String: Any],
              let media = configuration["media_attachments"] as? [String: Any] else {
            return fallback
        }
        let maxBytes = media["image_size_limit"] as? Int ?? fallback.maxBytes
        let matrix = media["image_matrix_limit"] as? Int
        return MediaLimit(maxBytes: maxBytes, maxDimension: matrix.map { Int(Double($0).squareRoot()) } ?? fallback.maxDimension)
    }

    private static func publishBluesky(post: NormalizedPost, context: SyndicationContext) async throws -> SyndicationResult {
        guard let identifier = context.env["BLUESKY_IDENTIFIER"], !identifier.isEmpty,
              let password = context.env["BLUESKY_APP_PASSWORD"], !password.isEmpty else {
            return .failed("Missing Bluesky credentials.")
        }

        let session = try await jsonRequest(
            url: "https://bsky.social/xrpc/com.atproto.server.createSession",
            method: "POST",
            body: ["identifier": identifier, "password": password],
            headers: ["Content-Type": "application/json"],
            context: context
        )
        guard let accessJwt = session["accessJwt"] as? String, let did = session["did"] as? String else {
            return .failed("Bluesky login did not return a session.")
        }

        var images: [[String: Any]] = []
        for photoPath in post.sourcePhotos.prefix(4) {
            let media = try SyndicationMedia.prepareImage(source: URL(fileURLWithPath: photoPath), limit: MediaLimit(maxBytes: 1_000_000, maxDimension: 2000))
            var upload = URLRequest(url: URL(string: "https://bsky.social/xrpc/com.atproto.repo.uploadBlob")!)
            upload.httpMethod = "POST"
            upload.setValue("Bearer \(accessJwt)", forHTTPHeaderField: "Authorization")
            upload.setValue(media.mimeType, forHTTPHeaderField: "Content-Type")
            upload.httpBody = media.bytes
            let response = try await context.http(upload)
            guard (200..<300).contains(response.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let blob = json["blob"] as? [String: Any] else {
                return .failed("Bluesky media upload returned \(response.statusCode).")
            }
            images.append(["alt": post.alt ?? "", "image": blob])
        }

        let text = String(SyndicationText.text(for: post).prefix(300))
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": text,
            "createdAt": ISO8601DateFormatter().string(from: context.now())
        ]
        let facets = blueskyLinkFacets(in: text)
        if !facets.isEmpty {
            record["facets"] = facets
        }
        if !images.isEmpty {
            record["embed"] = ["$type": "app.bsky.embed.images", "images": images]
        }
        let result = try await jsonRequest(
            url: "https://bsky.social/xrpc/com.atproto.repo.createRecord",
            method: "POST",
            body: ["repo": did, "collection": "app.bsky.feed.post", "record": record],
            headers: ["Authorization": "Bearer \(accessJwt)", "Content-Type": "application/json"],
            context: context
        )
        guard let uri = result["uri"] as? String else {
            return .failed("Bluesky did not return a post URI.")
        }
        let cid = result["cid"] as? String
        let id = uri.split(separator: "/").last.map(String.init) ?? uri
        return SyndicationResult(status: .published, fields: [
            "uri": uri,
            "cid": cid,
            "url": "https://bsky.app/profile/\(identifier)/post/\(id)",
            "publishedAt": ISO8601DateFormatter().string(from: context.now())
        ].compactMapValues { $0 })
    }

    private static func blueskyLinkFacets(in text: String) -> [[String: Any]] {
        let pattern = #"https?://[^\s<>()\[\]{}"]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            var end = range.upperBound
            while end > range.lowerBound, let scalar = text[..<end].unicodeScalars.last, ".!?,:;".unicodeScalars.contains(scalar) {
                end = text.index(before: end)
            }
            guard end > range.lowerBound else { return nil }
            let uri = String(text[range.lowerBound..<end])
            return [
                "index": [
                    "byteStart": text[..<range.lowerBound].utf8.count,
                    "byteEnd": text[..<end].utf8.count
                ],
                "features": [
                    [
                        "$type": "app.bsky.richtext.facet#link",
                        "uri": uri
                    ]
                ]
            ]
        }
    }

    private static func publishFlickr(post: NormalizedPost, context: SyndicationContext) async throws -> SyndicationResult {
        guard let photoPath = post.sourcePhotos.first else {
            return .failed("Flickr syndication requires a photo.")
        }
        guard let apiKey = context.env["FLICKR_API_KEY"], let apiSecret = context.env["FLICKR_API_SECRET"],
              let accessToken = context.env["FLICKR_ACCESS_TOKEN"], let accessSecret = context.env["FLICKR_ACCESS_SECRET"],
              !apiKey.isEmpty, !apiSecret.isEmpty, !accessToken.isEmpty, !accessSecret.isEmpty else {
            return .failed("Missing Flickr credentials.")
        }

        let uploadURL = "https://up.flickr.com/services/upload/"
        let oauth = [
            "oauth_consumer_key": apiKey,
            "oauth_nonce": context.nonce(),
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": "\(Int(context.now().timeIntervalSince1970))",
            "oauth_token": accessToken,
            "oauth_version": "1.0"
        ]
        let text = SyndicationText.markdownToText(post.parsed.body)
        var params = oauth
        params["title"] = post.title ?? ""
        params["description"] = text
        params["oauth_signature"] = oauthSignature(method: "POST", url: uploadURL, params: params, apiSecret: apiSecret, accessSecret: accessSecret)

        let bytes = try Data(contentsOf: URL(fileURLWithPath: photoPath))
        let boundary = "InksteadWriterBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var form = MultipartForm(boundary: boundary)
        for (key, value) in params { form.addField(name: key, value: value) }
        form.addFile(name: "photo", filename: URL(fileURLWithPath: photoPath).lastPathComponent, mimeType: Mime.fromPath(photoPath), bytes: bytes)
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body()
        let response = try await context.http(request)
        let xml = String(data: response.body, encoding: .utf8) ?? ""
        guard (200..<300).contains(response.statusCode), xml.contains("stat=\"ok\"") else {
            return .failed("Flickr upload failed: \(String(xml.prefix(200)))")
        }
        let id = xml.firstMatch(#"<photoid>([^<]+)</photoid>"#)
        return SyndicationResult(status: .published, fields: [
            "id": id,
            "url": id.map { "https://www.flickr.com/photo.gne?id=\($0)" },
            "publishedAt": ISO8601DateFormatter().string(from: context.now())
        ].compactMapValues { $0 })
    }

    private static func jsonRequest(url: String, method: String, body: [String: Any], headers: [String: String], context: SyndicationContext) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response = try await context.http(request)
        guard (200..<300).contains(response.statusCode) else {
            throw InksteadWriterError.io("\(url) returned \(response.statusCode).")
        }
        return (try JSONSerialization.jsonObject(with: response.body) as? [String: Any]) ?? [:]
    }

    private static func oauthSignature(method: String, url: String, params: [String: String], apiSecret: String, accessSecret: String) -> String {
        let parameterString = params.sorted { $0.key < $1.key }.map { "\(oauthEncode($0.key))=\(oauthEncode($0.value))" }.joined(separator: "&")
        let base = "\(method.uppercased())&\(oauthEncode(url))&\(oauthEncode(parameterString))"
        return HMACSHA1.sign(message: base, key: "\(oauthEncode(apiSecret))&\(oauthEncode(accessSecret))").base64EncodedString()
    }

    private static func oauthEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct MultipartForm {
    var boundary: String
    private var parts: [Data] = []

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, bytes: Data) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8) + bytes + Data("\r\n".utf8))
    }

    func body() -> Data {
        parts.reduce(Data(), +) + Data("--\(boundary)--\r\n".utf8)
    }
}

private enum HMACSHA1 {
    static func sign(message: String, key: String) -> Data {
        let blockSize = 64
        var keyBytes = [UInt8](key.data(using: .utf8) ?? Data())
        if keyBytes.count > blockSize {
            keyBytes = SHA1.digestBytes(Data(keyBytes))
        }
        if keyBytes.count < blockSize {
            keyBytes += [UInt8](repeating: 0, count: blockSize - keyBytes.count)
        }
        let outer = Data(keyBytes.map { $0 ^ 0x5c })
        let inner = Data(keyBytes.map { $0 ^ 0x36 })
        return Data(SHA1.digestBytes(outer + Data(SHA1.digestBytes(inner + Data(message.utf8)))))
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
