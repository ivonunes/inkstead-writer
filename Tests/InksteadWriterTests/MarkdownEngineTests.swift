import XCTest
@testable import InksteadWriter

final class MarkdownEngineTests: XCTestCase {
    func testNestedLists() {
        let html = MarkdownRenderer.render("""
        - parent
          - child
          - second child
        - sibling
        """)

        XCTAssertTrue(html.contains("<ul>\n<li>parent\n<ul>\n<li>child</li>\n<li>second child</li>\n</ul>\n</li>\n<li>sibling</li>\n</ul>"))
    }

    func testBlockquoteContainingList() {
        let html = MarkdownRenderer.render("""
        > Quote intro.
        >
        > - item one
        > - item two
        """)

        XCTAssertTrue(html.contains("<blockquote>\n<p>Quote intro.</p>\n<ul>\n<li>item one</li>\n<li>item two</li>\n</ul>\n</blockquote>"))
    }

    func testGfmTable() {
        let html = MarkdownRenderer.render("""
        | Name | Value |
        | ---- | ----- |
        | one  | 1     |
        """)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>one</td>"))
        XCTAssertTrue(html.contains("</table>"))
    }

    func testStrikethrough() {
        XCTAssertEqual(MarkdownRenderer.inline("~~gone~~ kept"), "<del>gone</del> kept")
    }

    func testTaskList() {
        let html = MarkdownRenderer.render("""
        - [ ] open task
        - [x] done task
        """)

        XCTAssertTrue(html.contains(#"<li><input type="checkbox" disabled="">"#))
        XCTAssertTrue(html.contains(#"<li><input type="checkbox" checked="" disabled="">"#))
        XCTAssertTrue(html.contains("open task"))
        XCTAssertTrue(html.contains("done task"))
    }

    func testAutolink() {
        XCTAssertEqual(
            MarkdownRenderer.inline("Visit https://example.com/page today"),
            #"Visit <a href="https://example.com/page">https://example.com/page</a> today"#
        )
        XCTAssertEqual(
            MarkdownRenderer.inline("See www.example.com too"),
            #"See <a href="http://www.example.com">www.example.com</a> too"#
        )
    }

    func testReferenceLinks() {
        let html = MarkdownRenderer.render("""
        A [reference link][site] in text.

        [site]: https://example.com "Example"
        """)

        XCTAssertTrue(html.contains(#"<a href="https://example.com" title="Example">reference link</a>"#))
    }

    func testRawHtmlBlockPassesThrough() {
        let html = MarkdownRenderer.render("""
        <figure class="wide">
          <img src="/media/a.jpg" alt="">
          <figcaption>Caption</figcaption>
        </figure>

        After the figure.
        """)

        XCTAssertTrue(html.contains(#"<figure class="wide">"#))
        XCTAssertTrue(html.contains("<figcaption>Caption</figcaption>"))
        XCTAssertTrue(html.contains("<p>After the figure.</p>"))
    }

    func testRawHtmlOmittedWhenDisabled() {
        var config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        config.markdown = MarkdownConfig(html: false, breaks: true)
        let html = MarkdownRenderer.render("<div>raw</div>\n\nInline <em>tag</em> here.", config: config)

        XCTAssertFalse(html.contains("<div>"))
        XCTAssertFalse(html.contains("<em>"))
        XCTAssertTrue(html.contains("Inline"))
    }

    func testSoftBreaksStayWhenBreaksDisabled() {
        var config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))
        config.markdown = MarkdownConfig(html: true, breaks: false)
        let html = MarkdownRenderer.render("Line one\nLine two", config: config)

        XCTAssertFalse(html.contains("<br>"))
        XCTAssertTrue(html.contains("Line one"))
        XCTAssertTrue(html.contains("Line two"))
    }

    func testFootnotes() {
        let html = MarkdownRenderer.render("""
        Body text[^1] continues.

        [^1]: The footnote text.
        """)

        XCTAssertTrue(html.contains(#"class="footnote-ref""#))
        XCTAssertTrue(html.contains("footnotes"))
        XCTAssertTrue(html.contains("The footnote text."))
    }

    func testSmartPunctuationSkipsCodeSpansAndBlocks() {
        let html = MarkdownRenderer.render("""
        Waiting... "quoted" -- dash

        ```
        raw... "literal" -- here
        ```
        """)

        XCTAssertTrue(html.contains("<p>Waiting… “quoted” – dash</p>"))
        XCTAssertTrue(html.contains("raw... &quot;literal&quot; -- here"))
    }

    func testHeadingsRequireSpaceAfterHashes() {
        XCTAssertTrue(MarkdownRenderer.render("### Heading").contains("<h3>Heading</h3>"))
        XCTAssertTrue(MarkdownRenderer.render("#nohashtag").contains("<p>#nohashtag</p>"))
    }
}
