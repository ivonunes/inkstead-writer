import XCTest
@testable import InksteadWriter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SyndicationTests: XCTestCase {
    func testSyndicationTextForNotesAndArticles() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        try """
        ---
        date: 2026-05-13T18:30:00+01:00
        syndicate:
          - mastodon
        ---

        Thinking about **bold** and _italic_ notes with a [link](https://example.com/post).

        `code` is okay.

        ![](/media/sample.jpg)
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-13-note.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Article
        date: 2026-05-14T18:30:00+01:00
        ---

        Body.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-14-article.md"), atomically: true, encoding: .utf8)

        let posts = try ContentLoader.loadPosts(root: root.url, config: config)
        let note = try XCTUnwrap(posts.first { $0.slug == "2026-05-13-note" })
        let article = try XCTUnwrap(posts.first { $0.slug == "2026-05-14-article" })

        XCTAssertEqual(SyndicationText.text(for: note), "Thinking about bold and italic notes with a link (https://example.com/post).\n\ncode is okay.")
        XCTAssertEqual(SyndicationText.text(for: article), "Article\nhttps://example.com/2026/05/14/article/")
    }

    func testUpdatesOnlySyndicationFrontmatterAndPreservesBody() {
        let original = "---\ndate: 2026-05-10T18:30:00+01:00\nsyndicate:\n  - mastodon\n---\n\nBody **must** stay.\n\n"
        let updated = SyndicationFrontmatter.update(markdown: original, provider: .mastodon, result: SyndicationResult(status: .published, fields: ["url": "https://example.com/1"]))

        XCTAssertTrue(updated.contains("syndication:"))
        XCTAssertTrue(updated.contains("mastodon:"))
        XCTAssertTrue(updated.contains("status: published"))
        XCTAssertTrue(updated.contains("https://example.com/1"))
        XCTAssertTrue(updated.hasSuffix("\nBody **must** stay.\n"))
    }

    func testPreparedMediaUsesOriginalWhenItFitsLimitsAndRejectsImpossibleLimits() throws {
        let root = try TemporaryDirectory()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        let source = root.url.appendingPathComponent("small.png")
        try png.write(to: source)

        let prepared = try SyndicationMedia.prepareImage(source: source, limit: MediaLimit(maxBytes: 100_000, maxDimension: 800))
        XCTAssertFalse(prepared.generated)
        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertEqual(prepared.bytes, png)

        XCTAssertThrowsError(try SyndicationMedia.prepareImage(source: source, limit: MediaLimit(maxBytes: 10, maxDimension: 800)))
    }

    func testPreparedMediaReencodesOversizedImages() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("large.jpg")
        try testJPEGData(width: 200, height: 150).write(to: source)

        let prepared = try SyndicationMedia.prepareImage(source: source, limit: MediaLimit(maxBytes: 1_000_000, maxDimension: 100))
        let dimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: prepared.bytes, mimeType: prepared.mimeType))

        XCTAssertTrue(prepared.generated)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(dimensions.width, 100)
        XCTAssertEqual(dimensions.height, 75)
    }

    func testPreparedMediaReencodesOversizedWebPImages() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("large.webp")
        try testWebPData(width: 200, height: 150).write(to: source)

        let prepared = try SyndicationMedia.prepareImage(source: source, limit: MediaLimit(maxBytes: 1_000_000, maxDimension: 100))
        let dimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: prepared.bytes, mimeType: prepared.mimeType))

        XCTAssertTrue(prepared.generated)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(dimensions.width, 100)
        XCTAssertEqual(dimensions.height, 75)
    }

    func testProvidersReportMissingCredentials() async throws {
        let post = try samplePost()
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: [:]) { _ in
            XCTFail("HTTP should not be called without credentials")
            return HTTPResponse(statusCode: 500)
        }

        let mastodon = await SyndicationProviders.publish(.mastodon, post: post, context: context)
        let bluesky = await SyndicationProviders.publish(.bluesky, post: post, context: context)
        let flickr = await SyndicationProviders.publish(.flickr, post: post, context: context)
        XCTAssertEqual(mastodon.status, .failed)
        XCTAssertEqual(bluesky.status, .failed)
        XCTAssertEqual(flickr.status, .failed)
    }

    func testMastodonPublishesStatusThroughHTTPClient() async throws {
        let post = try samplePost(title: "Article")
        var requests: [URLRequest] = []
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: [
            "MASTODON_INSTANCE_URL": "https://mastodon.example",
            "MASTODON_ACCESS_TOKEN": "token"
        ]) { request in
            requests.append(request)
            if request.url?.path == "/api/v2/instance" {
                return HTTPResponse(statusCode: 200, body: Data(#"{"configuration":{"media_attachments":{"image_size_limit":1000000,"image_matrix_limit":16000000}}}"#.utf8))
            }
            return HTTPResponse(statusCode: 200, body: Data(#"{"id":"1","url":"https://mastodon.example/@me/1"}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.mastodon, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(result.fields["id"], "1")
        XCTAssertEqual(result.fields["url"], "https://mastodon.example/@me/1")
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/statuses" })
    }

    func testMastodonUploadsPhotoBeforePublishingStatus() async throws {
        let post = try samplePhotoPost(body: "Photo caption.", extension: "png", data: testPNGData(width: 2, height: 2), alt: "A tiny test image.")
        var uploadBody = ""
        var statusBody: [String: Any] = [:]
        let context = SyndicationContext(root: post.path.deletingLastPathComponent(), env: [
            "MASTODON_INSTANCE_URL": "https://mastodon.example",
            "MASTODON_ACCESS_TOKEN": "token"
        ]) { request in
            switch request.url?.path {
            case "/api/v2/instance":
                return HTTPResponse(statusCode: 200, body: Data(#"{"configuration":{"media_attachments":{"image_size_limit":1000000,"image_matrix_limit":16000000}}}"#.utf8))
            case "/api/v2/media":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
                uploadBody = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                return HTTPResponse(statusCode: 200, body: Data(#"{"id":"media-1"}"#.utf8))
            case "/api/v1/statuses":
                statusBody = try XCTUnwrap(self.jsonObject(request.httpBody) as? [String: Any])
                return HTTPResponse(statusCode: 200, body: Data(#"{"id":"status-1","url":"https://mastodon.example/@me/status-1"}"#.utf8))
            default:
                XCTFail("Unexpected Mastodon request \(request.url?.absoluteString ?? "<nil>")")
                return HTTPResponse(statusCode: 500)
            }
        }

        let result = await SyndicationProviders.publish(.mastodon, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(result.fields["id"], "status-1")
        XCTAssertTrue(uploadBody.contains(#"name="file"; filename="photo.png""#))
        XCTAssertTrue(uploadBody.contains(#"name="description""#))
        XCTAssertTrue(uploadBody.contains("A tiny test image."))
        XCTAssertEqual(statusBody["status"] as? String, "Photo caption.")
        XCTAssertEqual(statusBody["media_ids"] as? [String], ["media-1"])
    }

    func testBlueskyPublishesRecordWithImageEmbed() async throws {
        let image = try testPNGData(width: 2, height: 2)
        let post = try samplePhotoPost(body: "Photo caption.", extension: "png", data: image, alt: "A tiny test image.")
        var createRecordBody: [String: Any] = [:]
        var uploadBody: Data?
        let context = SyndicationContext(
            root: post.path.deletingLastPathComponent(),
            env: [
                "BLUESKY_IDENTIFIER": "me.test",
                "BLUESKY_APP_PASSWORD": "app-password"
            ],
            http: { request in
                switch request.url?.absoluteString {
                case "https://bsky.social/xrpc/com.atproto.server.createSession":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let body = try XCTUnwrap(self.jsonObject(request.httpBody) as? [String: Any])
                    XCTAssertEqual(body["identifier"] as? String, "me.test")
                    XCTAssertEqual(body["password"] as? String, "app-password")
                    return HTTPResponse(statusCode: 200, body: Data(#"{"accessJwt":"jwt","did":"did:plc:123"}"#.utf8))
                case "https://bsky.social/xrpc/com.atproto.repo.uploadBlob":
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
                    uploadBody = request.httpBody
                    return HTTPResponse(statusCode: 200, body: Data(#"{"blob":{"$type":"blob","ref":{"$link":"blob-cid"},"mimeType":"image/png","size":68}}"#.utf8))
                case "https://bsky.social/xrpc/com.atproto.repo.createRecord":
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
                    createRecordBody = try XCTUnwrap(self.jsonObject(request.httpBody) as? [String: Any])
                    return HTTPResponse(statusCode: 200, body: Data(#"{"uri":"at://did:plc:123/app.bsky.feed.post/abc","cid":"record-cid"}"#.utf8))
                default:
                    XCTFail("Unexpected Bluesky request \(request.url?.absoluteString ?? "<nil>")")
                    return HTTPResponse(statusCode: 500)
                }
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = await SyndicationProviders.publish(.bluesky, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(result.fields["uri"], "at://did:plc:123/app.bsky.feed.post/abc")
        XCTAssertEqual(result.fields["cid"], "record-cid")
        XCTAssertEqual(result.fields["url"], "https://bsky.app/profile/me.test/post/abc")
        XCTAssertEqual(uploadBody, image)
        XCTAssertEqual(createRecordBody["repo"] as? String, "did:plc:123")
        XCTAssertEqual(createRecordBody["collection"] as? String, "app.bsky.feed.post")
        let record = try XCTUnwrap(createRecordBody["record"] as? [String: Any])
        XCTAssertEqual(record["text"] as? String, "Photo caption.")
        XCTAssertEqual(record["createdAt"] as? String, "2023-11-14T22:13:20Z")
        let embed = try XCTUnwrap(record["embed"] as? [String: Any])
        XCTAssertEqual(embed["$type"] as? String, "app.bsky.embed.images")
        let images = try XCTUnwrap(embed["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?["alt"] as? String, "A tiny test image.")
    }

    func testBlueskyPublishesLinkFacetsForCanonicalUrl() async throws {
        let post = try samplePost(title: "Café Notes")
        var createRecordBody: [String: Any] = [:]
        let context = SyndicationContext(
            root: post.path.deletingLastPathComponent(),
            env: [
                "BLUESKY_IDENTIFIER": "me.test",
                "BLUESKY_APP_PASSWORD": "app-password"
            ],
            http: { request in
                switch request.url?.absoluteString {
                case "https://bsky.social/xrpc/com.atproto.server.createSession":
                    return HTTPResponse(statusCode: 200, body: Data(#"{"accessJwt":"jwt","did":"did:plc:123"}"#.utf8))
                case "https://bsky.social/xrpc/com.atproto.repo.createRecord":
                    createRecordBody = try XCTUnwrap(self.jsonObject(request.httpBody) as? [String: Any])
                    return HTTPResponse(statusCode: 200, body: Data(#"{"uri":"at://did:plc:123/app.bsky.feed.post/abc","cid":"record-cid"}"#.utf8))
                default:
                    XCTFail("Unexpected Bluesky request \(request.url?.absoluteString ?? "<nil>")")
                    return HTTPResponse(statusCode: 500)
                }
            }
        )

        let result = await SyndicationProviders.publish(.bluesky, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        let record = try XCTUnwrap(createRecordBody["record"] as? [String: Any])
        let text = try XCTUnwrap(record["text"] as? String)
        XCTAssertEqual(text, "Café Notes\nhttps://example.com/2026/05/10/post/")
        let facets = try XCTUnwrap(record["facets"] as? [[String: Any]])
        XCTAssertEqual(facets.count, 1)
        let facet = try XCTUnwrap(facets.first)
        let index = try XCTUnwrap(facet["index"] as? [String: Int])
        let linkStart = try XCTUnwrap(text.range(of: "https://"))
        XCTAssertEqual(index["byteStart"], text[..<linkStart.lowerBound].utf8.count)
        XCTAssertEqual(index["byteEnd"], text.utf8.count)
        let features = try XCTUnwrap(facet["features"] as? [[String: Any]])
        XCTAssertEqual(features.first?["$type"] as? String, "app.bsky.richtext.facet#link")
        XCTAssertEqual(features.first?["uri"] as? String, "https://example.com/2026/05/10/post/")
    }

    func testFlickrOAuthSignatureIsDeterministicForUploadParameters() async throws {
        let post = try samplePhotoPost(body: "", extension: "jpg", data: Data("fake image".utf8), alt: nil)
        var uploadBody = ""
        let context = SyndicationContext(
            root: post.path.deletingLastPathComponent(),
            env: [
                "FLICKR_API_KEY": "key",
                "FLICKR_API_SECRET": "secret",
                "FLICKR_ACCESS_TOKEN": "access",
                "FLICKR_ACCESS_SECRET": "access-secret"
            ],
            http: { request in
                uploadBody = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                return HTTPResponse(statusCode: 200, body: Data(#"<rsp stat="ok"><photoid>123</photoid></rsp>"#.utf8))
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            nonce: { "nonce" }
        )

        let result = await SyndicationProviders.publish(.flickr, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(multipartField("oauth_nonce", in: uploadBody), "nonce")
        XCTAssertEqual(multipartField("oauth_timestamp", in: uploadBody), "1700000000")
        XCTAssertEqual(multipartField("oauth_signature_method", in: uploadBody), "HMAC-SHA1")
        XCTAssertEqual(multipartField("title", in: uploadBody), "")
        XCTAssertEqual(multipartField("oauth_signature", in: uploadBody), "KGYgMhiOnSj1+CamidZ3F2fVKU4=")
    }

    func testFlickrLeavesTitleBlankWhenPhotoNoteHasNoTitle() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try Data("fake image".utf8).write(to: root.url.appendingPathComponent("content/media/photo.jpg"))
        try """
        ---
        date: 2026-05-10T18:30:00+01:00
        photos:
          - /media/photo.jpg
        ---

        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-photo.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        let post = try XCTUnwrap(ContentLoader.loadPosts(root: root.url, config: config).first)
        var uploadBody = ""
        let context = SyndicationContext(root: root.url, env: [
            "FLICKR_API_KEY": "key",
            "FLICKR_API_SECRET": "secret",
            "FLICKR_ACCESS_TOKEN": "token",
            "FLICKR_ACCESS_SECRET": "access"
        ]) { request in
            uploadBody = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return HTTPResponse(statusCode: 200, body: Data(#"<rsp stat="ok"><photoid>123</photoid></rsp>"#.utf8))
        }

        let result = await SyndicationProviders.publish(.flickr, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(multipartField("title", in: uploadBody), "")
    }

    func testFlickrUsesPlainTextCaptionForTitleAndDescription() async throws {
        let post = try samplePhotoPost(body: "Cat. ![Image](/media/photo.jpg)", extension: "jpg", data: Data("fake image".utf8), alt: nil)
        var uploadBody = ""
        let context = SyndicationContext(root: post.path.deletingLastPathComponent(), env: [
            "FLICKR_API_KEY": "key",
            "FLICKR_API_SECRET": "secret",
            "FLICKR_ACCESS_TOKEN": "token",
            "FLICKR_ACCESS_SECRET": "access"
        ]) { request in
            uploadBody = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return HTTPResponse(statusCode: 200, body: Data(#"<rsp stat="ok"><photoid>123</photoid></rsp>"#.utf8))
        }

        let result = await SyndicationProviders.publish(.flickr, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(multipartField("title", in: uploadBody), "")
        XCTAssertEqual(multipartField("description", in: uploadBody), "Cat.")
    }

    func testFlickrUsesPostTitleWhenPhotoNoteHasTitle() async throws {
        let post = try samplePhotoPost(title: "Cat Photo", body: "Cat. ![Image](/media/photo.jpg)", extension: "jpg", data: Data("fake image".utf8), alt: nil)
        var uploadBody = ""
        let context = SyndicationContext(root: post.path.deletingLastPathComponent(), env: [
            "FLICKR_API_KEY": "key",
            "FLICKR_API_SECRET": "secret",
            "FLICKR_ACCESS_TOKEN": "token",
            "FLICKR_ACCESS_SECRET": "access"
        ]) { request in
            uploadBody = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return HTTPResponse(statusCode: 200, body: Data(#"<rsp stat="ok"><photoid>123</photoid></rsp>"#.utf8))
        }

        let result = await SyndicationProviders.publish(.flickr, post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(multipartField("title", in: uploadBody), "Cat Photo")
        XCTAssertEqual(multipartField("description", in: uploadBody), "Cat.")
    }

    func testSyndicateSiteUpdatesFrontmatterAndSkipsAlreadyPublishedTargets() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        let postURL = root.url.appendingPathComponent("content/posts/2026-05-10-note.md")
        try """
        ---
        date: 2026-05-10T18:30:00+01:00
        syndicate:
          - mastodon
        ---

        Hello.
        """.write(to: postURL, atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            syndication: SyndicationConfig(providers: [.mastodon])
        )
        let result = await Syndicator.syndicateSite(root: root.url, config: config, env: [
            "MASTODON_INSTANCE_URL": "https://mastodon.example",
            "MASTODON_ACCESS_TOKEN": "token"
        ]) { request in
            if request.url?.path == "/api/v2/instance" { return HTTPResponse(statusCode: 404) }
            return HTTPResponse(statusCode: 200, body: Data(#"{"id":"1","url":"https://mastodon.example/@me/1"}"#.utf8))
        }

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.published, 1)
        let updated = try String(contentsOf: postURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("syndication:"))
        XCTAssertTrue(updated.contains("mastodon:"))
        XCTAssertTrue(updated.contains("status: published"))

        let skipped = await Syndicator.syndicateSite(root: root.url, config: config, env: [
            "MASTODON_INSTANCE_URL": "https://mastodon.example",
            "MASTODON_ACCESS_TOKEN": "token"
        ]) { _ in
            XCTFail("Published targets should be skipped")
            return HTTPResponse(statusCode: 500)
        }
        XCTAssertFalse(skipped.changed)
        XCTAssertEqual(skipped.published, 0)
    }

    private func samplePost(title: String? = nil) throws -> NormalizedPost {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        let body = title.map { "title: \($0)\n" } ?? ""
        try """
        ---
        \(body)date: 2026-05-10T18:30:00+01:00
        ---

        Hello.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-post.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        return try XCTUnwrap(ContentLoader.loadPosts(root: root.url, config: config).first)
    }

    private func samplePhotoPost(title: String? = nil, body: String, extension pathExtension: String, data: Data, alt: String?) throws -> NormalizedPost {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-swift-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        let filename = "photo.\(pathExtension)"
        try data.write(to: root.appendingPathComponent("content/media/\(filename)"))
        let titleLine = title.map { "title: \"\($0)\"\n" } ?? ""
        let altLine = alt.map { "alt: \"\($0)\"\n" } ?? ""
        try """
        ---
        \(titleLine)\
        date: 2026-05-10T18:30:00+01:00
        \(altLine)photos:
          - /media/\(filename)
        ---

        \(body)
        """.write(to: root.appendingPathComponent("content/posts/2026-05-10-photo.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        return try XCTUnwrap(ContentLoader.loadPosts(root: root, config: config).first)
    }

    private func jsonObject(_ data: Data?) throws -> Any {
        try JSONSerialization.jsonObject(with: try XCTUnwrap(data))
    }

    private func multipartField(_ name: String, in body: String) -> String? {
        let pattern = #"(?s)name="\#(NSRegularExpression.escapedPattern(for: name))"\r\n\r\n(.*?)\r\n--"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        guard let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}
