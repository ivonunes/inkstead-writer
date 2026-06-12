import XCTest
@testable import InksteadWriter

final class ContentPipelineTests: XCTestCase {
    private let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))

    private func makeParsed(_ frontmatter: [String: FrontmatterValue], body: String = "Hello world.") -> ParsedMarkdown {
        ParsedMarkdown(
            path: URL(fileURLWithPath: "/tmp/example.md"),
            slug: "example",
            frontmatter: frontmatter,
            body: body,
            html: MarkdownRenderer.render(body, config: config)
        )
    }

    func testDateParsingIsTimezoneIndependent() {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!
        defer { NSTimeZone.default = previous }

        XCTAssertEqual(ContentLoader.parseDate("2026-06-09T12:00:00"), ContentLoader.parseDate("2026-06-09T12:00:00Z"))
        XCTAssertEqual(ContentLoader.parseDate("2026-06-09"), ContentLoader.parseDate("2026-06-09T00:00:00Z"))
        XCTAssertEqual(ContentLoader.parseDate("2026-05-12T18:30:00+01:00"), ContentLoader.parseDate("2026-05-12T17:30:00Z"))
        XCTAssertNil(ContentLoader.parseDate("not a date"))
    }

    func testPostUrlPathAndDisplayDateUseUtc() throws {
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09T23:30:00Z")]), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(post.urlPath, "/2026/06/09/example/")
        XCTAssertEqual(ContentLoader.dateDisplay(post.date), "June 9, 2026")
    }

    func testPostUrlPathAndDisplayDateRespectConfiguredTimezone() throws {
        var zonedConfig = config
        zonedConfig.site.timezone = "America/New_York"
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-10T01:00:00Z")]), config: zonedConfig, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(post.urlPath, "/2026/06/09/example/")
        XCTAssertEqual(ContentLoader.dateDisplay(post.date, timeZone: try ContentLoader.siteTimeZone(zonedConfig)), "June 9, 2026")
    }

    func testConfiguredTimezoneIsMachineIndependent() throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!
        defer { NSTimeZone.default = previous }

        var zonedConfig = config
        zonedConfig.site.timezone = "America/New_York"
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-10T01:00:00Z")]), config: zonedConfig, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(post.urlPath, "/2026/06/09/example/")
    }

    func testInvalidTimezoneProducesClearError() {
        var zonedConfig = config
        zonedConfig.site.timezone = "Europe/Lisbonn"
        XCTAssertThrowsError(try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09T12:00:00Z")]), config: zonedConfig, root: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertTrue(String(describing: error).contains("site.timezone 'Europe/Lisbonn'"))
        }
    }

    func testDateOnlyFrontmatterIsAccepted() throws {
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09")]), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(post.date, ContentLoader.parseDate("2026-06-09T00:00:00Z"))
        XCTAssertEqual(post.urlPath, "/2026/06/09/example/")
    }

    func testMissingDateErrorDiffersFromUnparseableDateError() {
        XCTAssertThrowsError(try ContentLoader.normalizePost(makeParsed([:]), config: config, root: URL(fileURLWithPath: "/tmp"))) { error in
            guard case InksteadWriterError.config(let message) = error else { return XCTFail("unexpected error \(error)") }
            XCTAssertTrue(message.contains("missing required date frontmatter"))
        }
        XCTAssertThrowsError(try ContentLoader.normalizePost(makeParsed(["date": .string("yesterday")]), config: config, root: URL(fileURLWithPath: "/tmp"))) { error in
            guard case InksteadWriterError.config(let message) = error else { return XCTFail("unexpected error \(error)") }
            XCTAssertTrue(message.contains("could not parse date 'yesterday'"))
            XCTAssertTrue(message.contains("ISO 8601"))
        }
    }

    func testAutoExcerptKeepsParagraphsAndLinksWithoutMedia() throws {
        let body = """
        Intro with a [link](https://example.com) and **bold**.

        <figure><img src="/media/a.jpg"><figcaption>Caption text</figcaption></figure>

        More text here.
        """
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09")], body: body), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(post.excerpt.contains(#"<a href="https://example.com">link</a>"#))
        XCTAssertTrue(post.excerpt.contains("<strong>bold</strong>"))
        XCTAssertTrue(post.excerpt.contains("<p>More text here.</p>"))
        XCTAssertFalse(post.excerpt.contains("Caption text"))
        XCTAssertFalse(post.excerpt.contains("<figure"))
        XCTAssertFalse(post.excerpt.contains("<img"))
        XCTAssertFalse(post.hasMore)
        XCTAssertNotNil(ContentLoader.topLevelHTMLBlocks(post.excerpt), "excerpt must be balanced HTML")
    }

    func testAutoExcerptTakesWholeParagraphsUpToTheWordLimit() throws {
        let paragraphs = (1...10).map { index in
            (1...20).map { "p\(index)w\($0)" }.joined(separator: " ")
        }
        let body = paragraphs.joined(separator: "\n\n")
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09")], body: body), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(post.hasMore)
        // 20-word paragraphs accumulate until the 70-word limit: four kept.
        XCTAssertTrue(post.excerpt.contains("<p>p1w1"))
        XCTAssertTrue(post.excerpt.contains("p4w20…</p>"))
        XCTAssertFalse(post.excerpt.contains("p5w1"))
        XCTAssertNotNil(ContentLoader.topLevelHTMLBlocks(post.excerpt), "excerpt must be balanced HTML")
    }

    func testOversizedSingleParagraphFallsBackToTruncatedText() throws {
        let body = (1...200).map { "word\($0)" }.joined(separator: " ")
        let post = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09")], body: body), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(post.hasMore)
        XCTAssertTrue(post.excerpt.hasPrefix("<p>word1 word2"))
        XCTAssertTrue(post.excerpt.hasSuffix("…</p>"))
        XCTAssertFalse(post.excerpt.contains("word71"))
    }

    func testSummaryAndMoreMarkerExcerptsKeepRenderedHtml() throws {
        let summary = try ContentLoader.normalizePost(makeParsed(["date": .string("2026-06-09"), "summary": .string("Custom summary wins.")]), config: config, root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(summary.excerpt, "<p>Custom summary wins.</p>\n")
        XCTAssertTrue(summary.hasMore)

        let more = try ContentLoader.normalizePost(
            makeParsed(["date": .string("2026-06-09")], body: "Intro [paragraph](https://example.com).\n\n<!--more-->\n\nRest of the article."),
            config: config,
            root: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(more.excerpt, #"<p>Intro <a href="https://example.com">paragraph</a>.</p>"# + "\n")
        XCTAssertTrue(more.hasMore)
    }

    func testFrontmatterClosingMarkerAtEndOfFile() {
        let parsed = FrontmatterParser.parse("---\ntitle: Hi\n---")
        XCTAssertEqual(parsed.frontmatter["title"]?.string, "Hi")
        XCTAssertEqual(parsed.body, "")

        let crlf = FrontmatterParser.parse("---\r\ntitle: Hi\r\n---")
        XCTAssertEqual(crlf.frontmatter["title"]?.string, "Hi")
        XCTAssertEqual(crlf.body, "")

        let withBody = FrontmatterParser.parse("---\ntitle: Hi\n---\nBody here")
        XCTAssertEqual(withBody.frontmatter["title"]?.string, "Hi")
        XCTAssertEqual(withBody.body, "Body here")
    }

    func testCollectionItemsSortByOrderThenDateThenFallbacks() throws {
        let root = try TemporaryDirectory()
        let directory = root.url.appendingPathComponent("content/collections/projects")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let items: [(String, String)] = [
            ("alpha", "---\norder: 2\n---\n\nAlpha"),
            ("bravo", "---\norder: 1\ndate: 2026-01-01T00:00:00Z\n---\n\nBravo"),
            ("echo", "---\norder: 1\ndate: 2026-03-01T00:00:00Z\n---\n\nEcho"),
            ("charlie", "---\ndate: 2026-01-02T00:00:00Z\n---\n\nCharlie"),
            ("delta", "---\ndate: 2026-01-01T00:00:00Z\n---\n\nDelta")
        ]
        for (slug, contents) in items {
            try contents.write(to: directory.appendingPathComponent("\(slug).md"), atomically: true, encoding: .utf8)
        }

        let collections = try ContentLoader.loadCollections(root: root.url, config: config)
        XCTAssertEqual(collections["projects"]?.map(\.slug), ["echo", "bravo", "alpha", "charlie", "delta"])
    }

    func testCollectionItemRelativePathIsPrefixBased() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("content/collections/projects/sample.md")
        let parsed = ParsedMarkdown(path: file, slug: "sample", frontmatter: [:], body: "", html: "")
        let item = ContentLoader.normalizeCollectionItem(parsed, collection: "projects", root: root.url)
        XCTAssertEqual(item.relativePath, "content/collections/projects/sample.md")
    }
}
