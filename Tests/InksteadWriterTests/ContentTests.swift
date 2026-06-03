import XCTest
@testable import InksteadWriter

final class ContentTests: XCTestCase {
    func testParsesFrontmatterAndNormalizesPhotoNote() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try "fake".write(to: root.url.appendingPathComponent("content/media/sample.jpg"), atomically: true, encoding: .utf8)
        let postURL = root.url.appendingPathComponent("content/posts/2026-05-12-photo-note.md")
        try """
        ---
        date: 2026-05-12T18:30:00+01:00
        syndicate:
          - mastodon
        categories:
          - Photography
        ---

        Thinking about notes with photos...

        ![](/media/sample.jpg)
        """.write(to: postURL, atomically: true, encoding: .utf8)

        let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        let posts = try ContentLoader.loadPosts(root: root.url, config: config)

        XCTAssertEqual(posts.first?.kind, .photoNote)
        XCTAssertEqual(posts.first?.firstImage, "/media/sample.jpg")
        XCTAssertEqual(posts.first?.categories, ["Photography"])
        XCTAssertEqual(posts.first?.syndicate ?? [], [.mastodon])
        XCTAssertEqual(posts.first?.sourcePhotos ?? [], [root.url.appendingPathComponent("content/media/sample.jpg").path])
    }

    func testMarkdownSyndicationTextMatchesWriterExpectations() {
        let text = MarkdownRenderer.plainTextForSyndication("""
        Thinking about **bold** and _italic_ notes with a [link](https://example.com/post).

        `code` is okay.

        ![](/media/sample.jpg)
        """)

        XCTAssertEqual(text, "Thinking about bold and italic notes with a link (https://example.com/post).\n\ncode is okay.")
    }

    func testMarkdownRendererSupportsCommonBlockSyntax() {
        let html = MarkdownRenderer.render("""
        ## Heading

        - one
        - **two**

        1. first
        2. second

        > Quoted [link](https://example.com).

        ```swift
        let value = "<escaped>"
        ```
        """)

        XCTAssertTrue(html.contains("<h2>Heading</h2>"))
        XCTAssertTrue(html.contains("<ul>\n<li>one</li>\n<li><strong>two</strong></li>\n</ul>"))
        XCTAssertTrue(html.contains("<ol>\n<li>first</li>\n<li>second</li>\n</ol>"))
        XCTAssertTrue(html.contains(#"<blockquote>"#))
        XCTAssertTrue(html.contains(#"<a href="https://example.com">link</a>"#))
        XCTAssertTrue(html.contains(#"<pre><code>let value = "&lt;escaped&gt;"</code></pre>"#))
    }

    func testMarkdownRendererDoesNotDoubleRenderHardBreaks() {
        let html = MarkdownRenderer.render("📍 Hakone, Japan  \n📷 Nikon F2")

        XCTAssertEqual(html, "<p>📍 Hakone, Japan<br>\n📷 Nikon F2</p>\n")
    }
}
