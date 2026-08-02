import XCTest
@testable import InksteadWriter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BufferSyndicationTests: XCTestCase {
    // MARK: - Target tokens

    func testTargetParsesProviderServiceAndAccount() {
        XCTAssertEqual(SyndicationTarget(rawValue: "mastodon"), .mastodon)
        XCTAssertEqual(SyndicationTarget(rawValue: "buffer:x"), .buffer("x"))
        XCTAssertEqual(SyndicationTarget(rawValue: "buffer:x@ivonunes"), .buffer("x", account: "ivonunes"))
        XCTAssertEqual(SyndicationTarget(rawValue: "buffer:x@ivonunes")?.account, "ivonunes")
    }

    func testTargetRoundTripsThroughItsRawValue() {
        for raw in ["mastodon", "bluesky", "buffer:x", "buffer:linkedin", "buffer:x@ivonunes"] {
            XCTAssertEqual(SyndicationTarget(rawValue: raw)?.rawValue, raw, raw)
        }
    }

    func testTargetRejectsUnknownProvidersAndMalformedTokens() {
        XCTAssertNil(SyndicationTarget(rawValue: "tumblr"))
        XCTAssertNil(SyndicationTarget(rawValue: "buffer:"))
        XCTAssertNil(SyndicationTarget(rawValue: "buffer:x@"))
        XCTAssertNil(SyndicationTarget(rawValue: ""))
    }

    // MARK: - Service aliases

    func testServiceAliasesTranslateBothWaysAndPassUnknownServicesThrough() {
        XCTAssertEqual(BufferChannels.token(forService: "twitter"), "x")
        // An alias is a compatibility surface once it is in a site's config, so
        // the raw service name a token may have been written with still matches.
        XCTAssertTrue(BufferChannels.matches(token: "x", service: "twitter"))
        XCTAssertTrue(BufferChannels.matches(token: "twitter", service: "twitter"))
        XCTAssertFalse(BufferChannels.matches(token: "x", service: "linkedin"))
        // A service Buffer adds tomorrow still resolves, under its own name.
        XCTAssertEqual(BufferChannels.token(forService: "somethingnew"), "somethingnew")
        XCTAssertTrue(BufferChannels.matches(token: "somethingnew", service: "somethingnew"))
    }

    func testOfferedServicesExcludeNativeAndUnsuitableOnes() {
        XCTAssertTrue(BufferChannels.isOffered(service: "twitter"))
        XCTAssertTrue(BufferChannels.isOffered(service: "linkedin"))
        XCTAssertTrue(BufferChannels.isOffered(service: "instagram"))
        // Connected directly, so offering them here would post twice.
        XCTAssertFalse(BufferChannels.isOffered(service: "mastodon"))
        XCTAssertFalse(BufferChannels.isOffered(service: "bluesky"))
        // Video, or publishes by pushing a reminder to a phone.
        XCTAssertFalse(BufferChannels.isOffered(service: "tiktok"))
        XCTAssertFalse(BufferChannels.isOffered(service: "youtube"))
    }

    // MARK: - What each channel accepts

    func testPhotoChannelsOnlyTakePhotoPosts() throws {
        let article = try samplePost(title: "Article")
        let photo = try samplePhotoPost()
        XCTAssertFalse(SyndicationProviders.canSyndicate(.buffer("instagram"), post: article))
        XCTAssertTrue(SyndicationProviders.canSyndicate(.buffer("instagram"), post: photo))
        XCTAssertFalse(SyndicationProviders.canSyndicate(.buffer("pinterest"), post: article))
        XCTAssertTrue(SyndicationProviders.canSyndicate(.buffer("pinterest"), post: photo))
    }

    func testLongFormChannelsSkipUntitledNotes() throws {
        let note = try samplePost()
        let article = try samplePost(title: "Why I Still Want a Personal Website")
        XCTAssertFalse(SyndicationProviders.canSyndicate(.buffer("linkedin"), post: note))
        XCTAssertTrue(SyndicationProviders.canSyndicate(.buffer("linkedin"), post: article))
        // Short-form channels still take both.
        XCTAssertTrue(SyndicationProviders.canSyndicate(.buffer("x"), post: note))
        XCTAssertTrue(SyndicationProviders.canSyndicate(.buffer("x"), post: article))
    }

    func testBufferTargetWithoutAChannelIsNotSyndicated() throws {
        let post = try samplePost(title: "Article")
        XCTAssertFalse(SyndicationProviders.canSyndicate(SyndicationTarget(provider: .buffer), post: post))
    }

    // MARK: - Post text

    func testLongFormChannelsPostTheArticleWithTheTitleAndLinkLast() throws {
        let post = try samplePost(title: "Why I Still Want a Personal Website", body: "The first paragraph.")
        let text = SyndicationProviders.bufferText(for: post, service: "linkedin")

        // The body leads, and the title says what the closing link opens.
        XCTAssertEqual(text, "The first paragraph.\n\nWhy I Still Want a Personal Website: \(post.canonicalUrl)")
    }

    func testLongFormTitleThatClosesItselfDoesNotGainAColon() throws {
        let post = try samplePost(title: "Why Bother?", body: "Body.")
        let text = SyndicationProviders.bufferText(for: post, service: "linkedin")

        XCTAssertTrue(text.hasSuffix("Why Bother? \(post.canonicalUrl)"), text)
        XCTAssertFalse(text.contains("?:"), text)
    }

    func testLongFormTextIsTrimmedToTheLimitAndKeepsTheLink() throws {
        let body = String(repeating: "word ", count: 900)
        let post = try samplePost(title: "Long", body: body)
        let text = SyndicationProviders.bufferText(for: post, service: "linkedin")

        XCTAssertLessThanOrEqual(text.count, 3000)
        XCTAssertTrue(text.hasSuffix("Long: \(post.canonicalUrl)"), String(text.suffix(80)))
        XCTAssertTrue(text.contains("…"))
    }

    func testTrimEndsOnAWordRatherThanMidWay() {
        let body = String(repeating: "alpha bravo ", count: 40)
        let trimmed = SyndicationText.trimmedBody(body, to: 50)

        XCTAssertLessThanOrEqual(trimmed.count, 50)
        XCTAssertTrue(trimmed.hasSuffix("…"), trimmed)
        // A cut on the character count alone would sever a word.
        let words = trimmed.dropLast().split(separator: " ")
        XCTAssertTrue(words.allSatisfy { $0 == "alpha" || $0 == "bravo" }, trimmed)
    }

    func testTrimPrefersParagraphBreakWhenOneIsCloseEnough() {
        let body = "First thought here.\n\nSecond thought that runs on and on past the room available."
        let trimmed = SyndicationText.trimmedBody(body, to: 30)

        XCTAssertEqual(trimmed, "First thought here.…")
    }

    func testTrimKeepsWholeBodiesUntouched() {
        XCTAssertEqual(SyndicationText.trimmedBody("Short enough.", to: 100), "Short enough.")
    }

    func testShortFormChannelsPostTheHeadlineAndLink() throws {
        let post = try samplePost(title: "Article", body: "Body text.")
        let text = SyndicationProviders.bufferText(for: post, service: "x")

        XCTAssertEqual(text, "Article\n\(post.canonicalUrl)")
    }

    // MARK: - Publishing

    func testPublishResolvesTheChannelFromTheServiceAndSharesNow() async throws {
        let post = try samplePost(title: "Article")
        var bodies: [[String: Any]] = []
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            bodies.append(body)
            let query = body["query"] as? String ?? ""
            if query.contains("organizations") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"account":{"organizations":[{"id":"org-1"}]}}}"#.utf8))
            }
            if query.contains("channels") {
                return HTTPResponse(statusCode: 200, body: Data(#"""
                {"data":{"channels":[{"id":"chan-x","name":"ivonunes","service":"twitter"},{"id":"chan-li","name":"Ivo","service":"linkedin"}]}}
                """#.utf8))
            }
            return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"createPost":{"post":{"id":"post-1"}}}}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("x"), post: post, context: context)

        XCTAssertEqual(result.status, .published)
        XCTAssertEqual(result.fields["id"], "post-1")
        let input = try XCTUnwrap((bodies.last?["variables"] as? [String: Any])?["input"] as? [String: Any])
        XCTAssertEqual(input["channelId"] as? String, "chan-x")
        XCTAssertEqual(input["mode"] as? String, "shareNow")
        // Never notificationPublishing: a post that turns into a phone reminder
        // has not been published, and nothing would say so.
        XCTAssertEqual(input["schedulingType"] as? String, "automaticPublishing")
    }

    func testPublishNeverFallsBackToAnotherAccountOnTheSameService() async throws {
        let post = try samplePost(title: "Article")
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            let query = body["query"] as? String ?? ""
            if query.contains("organizations") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"account":{"organizations":[{"id":"org-1"}]}}}"#.utf8))
            }
            if query.contains("channels") {
                return HTTPResponse(statusCode: 200, body: Data(#"""
                {"data":{"channels":[{"id":"chan-client","name":"clientco","service":"twitter"}]}}
                """#.utf8))
            }
            XCTFail("A post must not be created when the named account is absent")
            return HTTPResponse(statusCode: 500)
        }

        let result = await SyndicationProviders.publish(.buffer("x", account: "ivonunes"), post: post, context: context)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.fields["error"]?.contains("buffer:x@ivonunes") == true, result.fields["error"] ?? "")
    }

    func testPublishReportsMissingCredentialsWithoutCallingBuffer() async throws {
        let post = try samplePost(title: "Article")
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: [:]) { _ in
            XCTFail("Buffer should not be called without a key")
            return HTTPResponse(statusCode: 500)
        }

        let result = await SyndicationProviders.publish(.buffer("x"), post: post, context: context)
        XCTAssertEqual(result.status, .failed)
    }

    func testPublishSurfacesGraphQLErrorsReturnedWithA200() async throws {
        let post = try samplePost(title: "Article")
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { _ in
            HTTPResponse(statusCode: 200, body: Data(#"{"errors":[{"message":"Invalid API key"}]}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("x"), post: post, context: context)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.fields["error"]?.contains("Invalid API key") == true, result.fields["error"] ?? "")
    }

    /// A dead key is the one failure a site owner eventually hits without
    /// changing anything (Buffer keys last a year at most), so it must fail
    /// with reconnect wording rather than a raw GraphQL message.
    func testPublishGivesAnExpiredKeyReconnectWording() async throws {
        let post = try samplePost(title: "Article")
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { _ in
            HTTPResponse(statusCode: 200, body: Data(#"{"errors":[{"message":"An authentication JWT or Access Token is required","extensions":{"code":"UNAUTHENTICATED"}}]}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("x"), post: post, context: context)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.fields["error"]?.contains("reconnect Buffer in Inkstead") == true, result.fields["error"] ?? "")
        XCTAssertTrue(result.fields["error"]?.contains("BUFFER_API_KEY") == true, result.fields["error"] ?? "")
    }

    func testPhotoPostAttachesItsImageByPublicURL() async throws {
        let post = try samplePhotoPost()
        var input: [String: Any] = [:]
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            let query = body["query"] as? String ?? ""
            if query.contains("organizations") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"account":{"organizations":[{"id":"org-1"}]}}}"#.utf8))
            }
            if query.contains("channels") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"channels":[{"id":"chan-ig","name":"me","service":"instagram"}]}}"#.utf8))
            }
            input = (body["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
            return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"createPost":{"post":{"id":"post-1"}}}}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("instagram"), post: post, context: context)

        XCTAssertEqual(result.status, .published)
        let assets = try XCTUnwrap(input["assets"] as? [[String: Any]])
        let image = try XCTUnwrap(assets.first?["image"] as? [String: Any])
        // Buffer fetches media rather than accepting an upload, and syndication
        // runs after the deploy, so the post's own image is already reachable.
        XCTAssertEqual(image["url"] as? String, "https://example.com/media/photo.png")
        // The caption is the note's own text, as Flickr's description is.
        XCTAssertEqual(input["text"] as? String, "A caption.")
        XCTAssertEqual((image["metadata"] as? [String: Any])?["altText"] as? String, "A tiny picture.")
    }

    func testImageWithoutAltTextCarriesNoMetadata() async throws {
        let post = try samplePhotoPost(alt: nil)
        var input: [String: Any] = [:]
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            let query = body["query"] as? String ?? ""
            if query.contains("organizations") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"account":{"organizations":[{"id":"org-1"}]}}}"#.utf8))
            }
            if query.contains("channels") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"channels":[{"id":"chan-ig","name":"me","service":"instagram"}]}}"#.utf8))
            }
            input = (body["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
            return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"createPost":{"post":{"id":"post-1"}}}}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("instagram"), post: post, context: context)

        XCTAssertEqual(result.status, .published)
        let assets = try XCTUnwrap(input["assets"] as? [[String: Any]])
        // altText is required inside metadata, so the block is left out entirely
        // rather than sent empty.
        XCTAssertNil((assets.first?["image"] as? [String: Any])?["metadata"])
    }

    func testTitledArticleLeavesImageryToTheLinkPreview() async throws {
        let post = try samplePost(title: "Article", body: "Body with ![a picture](/media/photo.png) inline.")
        var input: [String: Any] = [:]
        let context = SyndicationContext(root: URL(fileURLWithPath: "/tmp"), env: ["BUFFER_API_KEY": "key"]) { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            let query = body["query"] as? String ?? ""
            if query.contains("organizations") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"account":{"organizations":[{"id":"org-1"}]}}}"#.utf8))
            }
            if query.contains("channels") {
                return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"channels":[{"id":"chan-fb","name":"Me","service":"facebook"}]}}"#.utf8))
            }
            input = (body["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
            return HTTPResponse(statusCode: 200, body: Data(#"{"data":{"createPost":{"post":{"id":"post-1"}}}}"#.utf8))
        }

        let result = await SyndicationProviders.publish(.buffer("facebook"), post: post, context: context)

        XCTAssertEqual(result.status, .published)
        // The unfurled link already shows the article's picture; attaching a
        // copy would put the same image in the post twice.
        XCTAssertNil(input["assets"])
    }

    // MARK: - Recorded results

    func testResultIsRecordedUnderTheProviderAndChannel() throws {
        let original = """
        ---
        title: Article
        ---

        Body.
        """
        let updated = SyndicationFrontmatter.update(
            markdown: original,
            target: .buffer("x"),
            result: SyndicationResult(status: .published, fields: ["id": "post-1"])
        )

        // The frontmatter parser splits mapping keys on their first colon, so a
        // channel is recorded nested under the provider rather than as buffer:x.
        XCTAssertFalse(updated.contains("buffer:x:"), updated)
        let parsed = FrontmatterParser.parse(updated).frontmatter
        let recorded = try XCTUnwrap(SyndicationFrontmatter.result(in: parsed["syndication"]?.object, for: .buffer("x")))
        XCTAssertEqual(recorded["status"]?.string, "published")
        XCTAssertEqual(recorded["id"]?.string, "post-1")
    }

    func testChannelsOnOneProviderRecordSeparateResults() throws {
        let first = SyndicationFrontmatter.update(
            markdown: "---\ntitle: Article\n---\n\nBody.",
            target: .buffer("x"),
            result: SyndicationResult(status: .published, fields: ["id": "post-1"])
        )
        let second = SyndicationFrontmatter.update(
            markdown: first,
            target: .buffer("linkedin"),
            result: SyndicationResult(status: .failed, fields: ["error": "nope"])
        )

        let syndication = FrontmatterParser.parse(second).frontmatter["syndication"]?.object
        XCTAssertEqual(SyndicationFrontmatter.result(in: syndication, for: .buffer("x"))?["status"]?.string, "published")
        XCTAssertEqual(SyndicationFrontmatter.result(in: syndication, for: .buffer("linkedin"))?["status"]?.string, "failed")
        // A recorded channel must not stand in for one that was never attempted,
        // or the next run would skip it silently.
        XCTAssertNil(SyndicationFrontmatter.result(in: syndication, for: .buffer("threads")))
    }

    func testDirectProvidersKeepRecordingDirectlyUnderTheirName() throws {
        let updated = SyndicationFrontmatter.update(
            markdown: "---\ntitle: Article\n---\n\nBody.",
            target: .mastodon,
            result: SyndicationResult(status: .published, fields: ["url": "https://mastodon.example/1"])
        )

        let syndication = FrontmatterParser.parse(updated).frontmatter["syndication"]?.object
        XCTAssertEqual(SyndicationFrontmatter.result(in: syndication, for: .mastodon)?["url"]?.string, "https://mastodon.example/1")
    }

    func testAccountScopedResultsAreRecordedSeparately() throws {
        let first = SyndicationFrontmatter.update(
            markdown: "---\ntitle: Article\n---\n\nBody.",
            target: .buffer("x", account: "ivonunes"),
            result: SyndicationResult(status: .published, fields: ["id": "a"])
        )
        let second = SyndicationFrontmatter.update(
            markdown: first,
            target: .buffer("x", account: "clientco"),
            result: SyndicationResult(status: .published, fields: ["id": "b"])
        )

        let syndication = FrontmatterParser.parse(second).frontmatter["syndication"]?.object
        XCTAssertEqual(SyndicationFrontmatter.result(in: syndication, for: .buffer("x", account: "ivonunes"))?["id"]?.string, "a")
        XCTAssertEqual(SyndicationFrontmatter.result(in: syndication, for: .buffer("x", account: "clientco"))?["id"]?.string, "b")
    }

    // MARK: - Config

    func testConfigKeepsChannelTokens() throws {
        let json = #"{"syndication":{"providers":["mastodon","buffer:x","buffer:linkedin","buffer:x@ivonunes"]}}"#
        struct Wrapper: Decodable { var syndication: SyndicationConfig }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))

        XCTAssertEqual(wrapper.syndication.providers, [
            .mastodon,
            .buffer("x"),
            .buffer("linkedin"),
            .buffer("x", account: "ivonunes")
        ])
    }

    // MARK: - Helpers

    private func samplePost(title: String? = nil, body: String = "Hello.") throws -> NormalizedPost {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        let titleLine = title.map { "title: \"\($0)\"\n" } ?? ""
        try """
        ---
        \(titleLine)date: 2026-05-10T18:30:00+01:00
        ---

        \(body)
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-post.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        return try XCTUnwrap(ContentLoader.loadPosts(root: root.url, config: config).first)
    }

    private func samplePhotoPost(alt: String? = "A tiny picture.") throws -> NormalizedPost {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.url.appendingPathComponent("content/media/photo.png"))
        let altLine = alt.map { "alt: \"\($0)\"\n" } ?? ""
        try """
        ---
        date: 2026-05-10T18:30:00+01:00
        \(altLine)photos:
          - /media/photo.png
        ---

        A caption.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-photo.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        return try XCTUnwrap(ContentLoader.loadPosts(root: root.url, config: config).first)
    }
}
