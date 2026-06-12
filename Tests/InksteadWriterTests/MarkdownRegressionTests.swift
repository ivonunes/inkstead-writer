import XCTest
@testable import InksteadWriter

final class MarkdownRegressionTests: XCTestCase {
    func testFencedCodeBlockKeepsBlankLines() {
        let html = MarkdownRenderer.render("""
        Intro paragraph.

        ```swift
        let a = 1

        let b = 2


        let c = 3
        ```

        After paragraph.
        """)

        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">let a = 1\n\nlet b = 2\n\n\nlet c = 3\n</code></pre>"))
        XCTAssertTrue(html.contains("<p>Intro paragraph.</p>"))
        XCTAssertTrue(html.contains("<p>After paragraph.</p>"))
    }

    func testStandardAsteriskEmphasis() {
        XCTAssertEqual(MarkdownRenderer.inline("some *emphasis* here"), "some <em>emphasis</em> here")
        XCTAssertEqual(MarkdownRenderer.inline("**strong** and *em*"), "<strong>strong</strong> and <em>em</em>")
        XCTAssertEqual(MarkdownRenderer.inline("***both***"), "<em><strong>both</strong></em>")
        XCTAssertEqual(MarkdownRenderer.inline("a ** b"), "a ** b")
    }

    func testLinkTitleDoesNotLeakIntoHref() {
        XCTAssertEqual(
            MarkdownRenderer.inline(#"[a](https://x "t")"#),
            #"<a href="https://x" title="t">a</a>"#
        )
        XCTAssertEqual(
            MarkdownRenderer.inline("[b](https://y)"),
            #"<a href="https://y">b</a>"#
        )
    }

    func testImageTitleStillExcludedFromSrc() {
        XCTAssertEqual(
            MarkdownRenderer.inline(#"![alt](/media/a.jpg "title")"#),
            #"<img src="/media/a.jpg" alt="alt" title="title">"#
        )
    }

    func testEllipsisSmarteningDoesNotCorruptCodeSpans() {
        XCTAssertEqual(
            MarkdownRenderer.inline("text... `code...` end"),
            "text… <code>code...</code> end"
        )
    }
}
