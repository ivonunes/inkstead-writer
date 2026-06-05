import XCTest
@testable import InksteadWriter

final class ThemeCheckTests: XCTestCase {
    func testChecksValidThemeComponentsAndStyleAndScriptFiles() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/components"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/styles"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/scripts"), withIntermediateDirectories: true)
        try ".card { color: red; }".write(to: root.url.appendingPathComponent("theme/styles/site.css"), atomically: true, encoding: .utf8)
        try #"document.documentElement.dataset.ready = "true";"#.write(to: root.url.appendingPathComponent("theme/scripts/site.js"), atomically: true, encoding: .utf8)
        try """
        let menu = page.query("#menu")
        on ".toggle".click {
          menu.toggleClass("is-open")
        }
        """.write(to: root.url.appendingPathComponent("theme/scripts/client.plume"), atomically: true, encoding: .utf8)
        try """
        @component Card(title) {
          @style(file: "../styles/site.css")
          @script(file: "../scripts/site.js")
          <article>@slot { <h2>{title}</h2> }</article>
        }
        """.write(to: root.url.appendingPathComponent("theme/components/Card.plume"), atomically: true, encoding: .utf8)
        try """
        @style(file: "styles/site.css")
        @script(file: "scripts/site.js")
        @script(file: "scripts/client.plume")
        @script {
          let menu = page.query("#menu")
          on ".toggle".click {
            menu.toggleClass("is-open")
          }
        }
        @Card("Hello") {
          <p>Body</p>
        }
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checkedFiles.contains("theme/home.plume"))
        XCTAssertTrue(result.checkedFiles.contains("theme/components/Card.plume"))
    }

    func testChecksFeedTemplatesWithSampleFeedContext() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        @style {
          body { color: CanvasText; }
        }
        @script(language: "javascript") {
          window.__feedReady = true;
        }
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>{feed.title}</title><link>{feed.siteUrl}</link>
        @if feed.category {
        <category>{feed.category.name}</category>
        }
        @if feed.presentationScriptSrc {
        <script xmlns="http://www.w3.org/1999/xhtml" src="{feed.presentationScriptSrc}"></script>
        }
        @for item in feed.items {
        <item><title>{item.title}</title><description><![CDATA[{item.html | raw}]]></description></item>
        }
        </channel></rss>
        """.write(to: root.url.appendingPathComponent("theme/feed.xml.plume"), atomically: true, encoding: .utf8)
        try """
        {
          "version": {feed.version | json},
          "title": {feed.title | json},
          "category": {feed.category.name | default("") | json},
          "items": [
            @for item in feed.items {
            {item.comma | raw}{ "id": {item.id | json}, "content_html": {item.contentHTML | json} }
            }
          ]
        }
        """.write(to: root.url.appendingPathComponent("theme/feed.json.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checkedFiles.contains("theme/feed.xml.plume"))
        XCTAssertTrue(result.checkedFiles.contains("theme/feed.json.plume"))
    }

    func testChecksNotFoundTemplateWithSampleContext() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/pages"), withIntermediateDirectories: true)
        try """
        <h1>{notFound.title}</h1>
        <p>{notFound.message}</p>
        """.write(to: root.url.appendingPathComponent("theme/pages/404.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checkedFiles.contains("theme/pages/404.plume"))
    }

    func testReportsThemeCheckIssues() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/components"), withIntermediateDirectories: true)
        try """
        @component Card(title) {
          <article>{title}</article>
        }
        """.write(to: root.url.appendingPathComponent("theme/components/Card.plume"), atomically: true, encoding: .utf8)
        try """
        @style(file: "styles/missing.css")
        @script(file: "scripts/missing.js")
        @script {
          let menu = page.query("#menu")
          menu.fly()
        }
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)
        try """
        @content(header) {
          <h1>Wrong place</h1>
        }
        """.write(to: root.url.appendingPathComponent("theme/page.plume"), atomically: true, encoding: .utf8)
        try """
        @Card("Hello", title: "Duplicate")
        """.write(to: root.url.appendingPathComponent("theme/post.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())
        let messages = result.issues.map(\.message).joined(separator: "\n")

        XCTAssertFalse(result.passed)
        XCTAssertTrue(messages.contains("Duplicate argument title for component Card"))
        XCTAssertTrue(messages.contains("Plume style file styles/missing.css was not found"))
        XCTAssertTrue(messages.contains("Plume script file scripts/missing.js was not found"))
        XCTAssertTrue(messages.contains("Unsupported Plume script method fly"))
        XCTAssertTrue(messages.contains("@content can only be used directly inside a component call"))
    }

    func testReportsThemeAssetImageErrorsAndWarnings() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try testPNGData(width: 24, height: 16).write(to: root.url.appendingPathComponent("theme/images/avatar.png"))
        try """
        <a href="{asset("images/missing.png")}">Missing</a>
        @image("images/avatar.png", alt: "")
        @image("/media/missing.jpg", alt: "Missing")
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())
        let messages = result.issues.map(\.message).joined(separator: "\n")

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(messages.contains("Plume asset images/missing.png was not found"))
        XCTAssertTrue(messages.contains("Plume asset /media/missing.jpg was not found"))
        XCTAssertTrue(messages.contains("@image should include meaningful alt text"))
    }

    func testThemeCheckPassesWithWarningsOnly() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/images"), withIntermediateDirectories: true)
        try testPNGData(width: 24, height: 16).write(to: root.url.appendingPathComponent("theme/images/avatar.png"))
        try """
        @image("images/avatar.png")
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeChecker.check(root: root.url, config: testConfig())

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.warnings.map(\.message), ["@image should include meaningful alt text."])
    }

    private func testConfig() -> InksteadWriterConfig {
        InksteadWriterConfig(site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"))
    }
}
