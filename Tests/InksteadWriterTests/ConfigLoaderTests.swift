import XCTest
@testable import InksteadWriter

final class ConfigLoaderTests: XCTestCase {
    func testLoadsCurrentTypeScriptConfigShape() throws {
        let config = try ConfigLoader.loadTypeScriptConfig("""
        import { defineConfig } from "inkstead";
        export default defineConfig({
          version: "1.2.0",
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
          data: {
            repos: {
              url: "https://api.example.com/repos",
              cache: "1h",
              headers: { Accept: "application/vnd.github+json" }
            },
            links: "data/links.json"
          },
          ci: { provider: "github-actions" },
          deploy: { provider: "github-pages" },
          connection: {
            provider: "github",
            repository: "me/site",
            branch: "main",
            categories: ["Photography", "Essays"]
          }
        });
        """)

        XCTAssertEqual(config.recordedVersion, "1.2.0")
        XCTAssertEqual(config.site.title, "My Website")
        XCTAssertEqual(config.deploy?.provider, .githubPages)
        XCTAssertEqual(config.connection?.categories, ["Photography", "Essays"])
        XCTAssertEqual(config.content.collections, "content/collections")
        XCTAssertEqual(config.data?["repos"]?.url, "https://api.example.com/repos")
        XCTAssertEqual(config.data?["repos"]?.cache, "1h")
        XCTAssertEqual(config.data?["repos"]?.headers?["Accept"], "application/vnd.github+json")
        XCTAssertEqual(config.data?["links"]?.file, "data/links.json")
    }

    func testRejectsIncompatiblePagesCiPairing() throws {
        XCTAssertThrowsError(try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
          ci: { provider: "gitlab-ci" },
          deploy: { provider: "github-pages" }
        });
        """))
    }

    func testRejectsSitesCreatedByNewerInksteadWriterVersion() throws {
        XCTAssertThrowsError(try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          version: "99.0.0",
          site: { title: "My Website", url: "https://example.com", author: "Your Name" }
        });
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("newer Inkstead Writer binary"))
        }
    }

    func testRejectsInvalidDataSourceConfigurations() throws {
        XCTAssertThrowsError(try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          data: {
            "bad-name": "data/example.json"
          }
        });
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("valid Plume identifier"))
        }

        XCTAssertThrowsError(try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          data: {
            links: { url: "https://example.com/links.json", file: "data/links.json" }
          }
        });
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("exactly one of url or file"))
        }
    }

    func testLoadsCurrentJSONConfigShapeWithTopLevelConnection() throws {
        let data = Data("""
        {
          "version": "2.0.0",
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "content": { "posts": "posts", "pages": "pages", "media": "media", "collections": "collections" },
          "connection": {
            "provider": "gitlab",
            "repository": "me/site",
            "branch": "main"
          },
          "data": {
            "links": { "path": "data/links.json" }
          }
        }
        """.utf8)

        let config = try JSONDecoder().decode(InksteadWriterConfig.self, from: data)

        XCTAssertEqual(config.recordedVersion, "2.0.0")
        XCTAssertEqual(config.content.collections, "collections")
        XCTAssertEqual(config.connection?.provider, .gitlab)
        XCTAssertEqual(config.connection?.repository, "me/site")
        XCTAssertEqual(config.data?["links"]?.file, "data/links.json")
    }

    func testSupportsLineAndBlockCommentsInTypeScriptConfig() throws {
        let config = try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          /* block comment
             spanning lines */
          site: {
            title: "My Website", // line comment
            url: "https://example.com", /* inline */ author: "Your Name"
          }
        });
        """)

        XCTAssertEqual(config.site.title, "My Website")
        XCTAssertEqual(config.site.author, "Your Name")
    }

    func testParseErrorsIncludeLineAndColumn() throws {
        XCTAssertThrowsError(try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          site: { title: "My Website",
            url: }
        });
        """)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 3"), message)
            XCTAssertTrue(message.contains("defineConfig literal"), message)
        }
    }

    func testDecodingErrorsIncludeFileNameAndCodingPath() throws {
        let root = try TemporaryDirectory()
        try Data("""
        {
          "site": { "title": "My Website", "url": "https://example.com", "author": 7 }
        }
        """.utf8).write(to: root.url.appendingPathComponent(InksteadWriterMetadata.configFileName))

        XCTAssertThrowsError(try ConfigLoader.load(root: root.url)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains(InksteadWriterMetadata.configFileName), message)
            XCTAssertTrue(message.contains("site.author"), message)
        }
    }

    func testLoadIfPresentDistinguishesAbsentFromInvalidConfig() throws {
        let empty = try TemporaryDirectory()
        XCTAssertNil(try ConfigLoader.loadIfPresent(root: empty.url))

        let broken = try TemporaryDirectory()
        try Data("{ not json".utf8).write(to: broken.url.appendingPathComponent(InksteadWriterMetadata.configFileName))
        XCTAssertThrowsError(try ConfigLoader.loadIfPresent(root: broken.url))

        let valid = try TemporaryDirectory()
        try Data("""
        {
          "version": "2.0.0",
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.utf8).write(to: valid.url.appendingPathComponent(InksteadWriterMetadata.configFileName))
        XCTAssertEqual(try ConfigLoader.loadIfPresent(root: valid.url)?.site.title, "My Website")
    }

    func testLegacyFlatWriterConfigDefaultsToLegacyVersionForMigrations() throws {
        let config = try ConfigLoader.loadTypeScriptConfig("""
        export default defineConfig({
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          writer: {
            enabled: true,
            provider: "github",
            owner: "me",
            repo: "site",
            branch: "main"
          }
        });
        """)

        XCTAssertEqual(config.recordedVersion, "1.2.0")
        XCTAssertEqual(config.connection?.repository, "me/site")
    }

    func testUnknownSyndicationProvidersAreDroppedNotFatal() throws {
        let root = try TemporaryDirectory()
        try """
        {
          "version": "2.1.0",
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "syndication": { "providers": ["mastodon", "x", "myspace"] }
        }
        """.write(to: root.url.appendingPathComponent("inkstead-writer.json"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        XCTAssertEqual(config.syndication?.providers, [.mastodon])
    }
}
