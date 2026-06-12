import Foundation
import XCTest
@testable import InksteadWriter

final class ThemeSerializationTests: XCTestCase {
    private let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))

    private func makePost(slug: String = "example") throws -> NormalizedPost {
        let body = "Hello world."
        let parsed = ParsedMarkdown(
            path: URL(fileURLWithPath: "/tmp/\(slug).md"),
            slug: slug,
            frontmatter: ["date": .string("2026-06-09T12:00:00Z"), "title": .string("Example")],
            body: body,
            html: MarkdownRenderer.render(body, config: config)
        )
        return try ContentLoader.normalizePost(parsed, config: config, root: URL(fileURLWithPath: "/tmp"))
    }

    func testSerializeCategoryReusesProvidedPostDictionaries() throws {
        let post = try makePost()
        let category = CategoryCollection(name: "Tech", slug: "tech", urlPath: "/categories/tech/", feedPath: "/categories/tech/feed.xml", posts: [post])
        let marker: [String: Any] = ["slug": "marker"]

        let serialized = serializeCategory(category, postsByURL: [post.canonicalUrl: marker], timeZone: ContentLoader.utcTimeZone)
        let posts = try XCTUnwrap(serialized["posts"] as? [[String: Any]])
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0]["slug"] as? String, "marker")

        let fallback = serializeCategory(category, timeZone: ContentLoader.utcTimeZone)
        let fallbackPosts = try XCTUnwrap(fallback["posts"] as? [[String: Any]])
        XCTAssertEqual(fallbackPosts[0]["slug"] as? String, post.slug)
    }

    func testFeedContextsEmbedProvidedSerializedCategory() throws {
        let post = try makePost()
        let category: [String: Any] = ["name": "Tech", "slug": "tech"]

        let rss = FeedRenderer.rssContext(config: config, posts: [post], category: category)
        XCTAssertEqual((rss["category"] as? [String: Any])?["slug"] as? String, "tech")

        let json = FeedRenderer.jsonContext(config: config, posts: [post], category: category)
        XCTAssertEqual((json["category"] as? [String: Any])?["slug"] as? String, "tech")

        XCTAssertTrue(FeedRenderer.rssContext(config: config, posts: [post])["category"] is NSNull)
        XCTAssertTrue(FeedRenderer.jsonContext(config: config, posts: [post])["category"] is NSNull)
    }

    func testSerializedPostUsesStableIsoAndUtcDisplayDates() throws {
        let post = try makePost()
        let serialized = serializePost(post, timeZone: ContentLoader.utcTimeZone)
        XCTAssertEqual(serialized["dateIso"] as? String, "2026-06-09T12:00:00Z")
        XCTAssertEqual(serialized["dateDisplay"] as? String, "June 9, 2026")
    }

    func testSerializedPostDisplayDatesRespectSiteTimezone() throws {
        let body = "Hello world."
        let parsed = ParsedMarkdown(
            path: URL(fileURLWithPath: "/tmp/example.md"),
            slug: "example",
            frontmatter: ["date": .string("2026-06-10T01:00:00Z"), "title": .string("Example")],
            body: body,
            html: MarkdownRenderer.render(body, config: config)
        )
        var zonedConfig = config
        zonedConfig.site.timezone = "America/New_York"
        let post = try ContentLoader.normalizePost(parsed, config: zonedConfig, root: URL(fileURLWithPath: "/tmp"))
        let serialized = serializePost(post, timeZone: try ContentLoader.siteTimeZone(zonedConfig))
        XCTAssertEqual(serialized["dateIso"] as? String, "2026-06-10T01:00:00Z")
        XCTAssertEqual(serialized["dateDisplay"] as? String, "June 9, 2026")
    }
}
