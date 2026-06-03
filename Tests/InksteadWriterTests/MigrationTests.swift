import XCTest
@testable import InksteadWriter

final class MigrationTests: XCTestCase {
    func testPlansAndAppliesLiquidToPlumeTemplateMigration() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "content": { "posts": "content/posts", "pages": "content/pages", "media": "content/media" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        {% comment %}safe to discard{% endcomment %}
        {% assign title = site.title | upcase %}
        {% if site.title %}{% assign subtitle = "Shown" %}{% endif %}
        {% if site.title %}Title{% elsif site.author %}Author{% else %}Untitled{% endif %}
        {% if currentPath == "/photos/" or currentPath contains "/photos/" or isPhotoActive %}active{% endif %}
        <h1>{{- title -}}</h1>
        """.write(to: root.url.appendingPathComponent("theme/home.liquid"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        let plan = try MigrationPlanner.plan(root: root.url, config: config)

        XCTAssertTrue(plan.actions.contains {
            if case .write("theme/home.plume", let content, "convert legacy template to Plume") = $0 {
                return content.contains("@let title = site.title | upcase")
                    && content.contains("@let subtitle = \"Shown\"")
                    && content.contains("@if site.title {\nTitle\n} else if site.author {\nAuthor\n} else {\nUntitled")
                    && content.contains(#"@if currentPath == "/photos/" || currentPath.contains("/photos/") || isPhotoActive {"#)
                    && content.contains("<h1>{title | raw}</h1>")
                    && !content.contains("safe to discard")
            }
            return false
        })
        XCTAssertTrue(plan.actions.contains(.delete(path: "theme/home.liquid")))
        XCTAssertTrue(plan.actions.contains {
            if case .write("inkstead-writer.json", _, _) = $0 { return true }
            return false
        })

        _ = try MigrationPlanner.apply(plan, root: root.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("theme/home.liquid").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("theme/home.plume").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: root.url.appendingPathComponent("inkstead-writer").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent(".gitignore").path))
        let migrated = try ConfigLoader.load(root: root.url)
        XCTAssertEqual(migrated.version, InksteadWriterMetadata.currentVersion)
    }

    func testMigrationRefreshesWrapperForCurrentSites() throws {
        let root = try TemporaryDirectory()
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "dist/\n".write(to: root.url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))
        XCTAssertTrue(plan.actions.contains(.write(path: "inkstead-writer", content: SiteWrapper.script, reason: "install versioned Inkstead Writer wrapper")))
        XCTAssertFalse(plan.actions.contains { action in
            if case .write(".gitignore", _, _) = action { return true }
            return false
        })

        _ = try MigrationPlanner.apply(plan, root: root.url)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: root.url.appendingPathComponent("inkstead-writer").path))
    }

    func testMigrationRunnerDryRunDoesNotApplyPlan() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "content": { "posts": "content/posts", "pages": "content/pages", "media": "content/media" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "<h1>{{ site.title }}</h1>".write(to: root.url.appendingPathComponent("theme/home.liquid"), atomically: true, encoding: .utf8)

        let result = try MigrationRunner.run(root: root.url, dryRun: true)

        XCTAssertTrue(result.dryRun)
        XCTAssertFalse(result.plan.actions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("theme/home.liquid").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("theme/home.plume").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("inkstead-writer").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("inkstead-writer.json").path))
    }

    func testLeavesUnsupportedLiquidTemplatesForManualMigration() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        { "inkstead": { "version": "1.2.0" }, "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" } }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "{% capture title %}Hi{% endcapture %}".write(to: root.url.appendingPathComponent("theme/layout.liquid"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))
        XCTAssertTrue(plan.actions.contains {
            if case .manual("theme/layout.liquid", let message) = $0 {
                return message.contains("capture")
            }
            return false
        })
        XCTAssertFalse(plan.actions.contains {
            if case .write("inkstead-writer.json", _, _) = $0 { return true }
            return false
        })
    }

    func testLeavesUnsupportedLiquidFiltersForManualMigration() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        { "inkstead": { "version": "1.2.0" }, "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" } }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "{{ site.title | totally_unknown_filter }}".write(to: root.url.appendingPathComponent("theme/home.liquid"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))
        XCTAssertTrue(plan.actions.contains {
            if case .manual("theme/home.liquid", let message) = $0 {
                return message.contains("totally_unknown_filter")
            }
            return false
        })
        XCTAssertFalse(plan.actions.contains {
            if case .write("theme/home.plume", _, _) = $0 { return true }
            return false
        })
    }

    func testDoesNotOverwriteExistingPlumeTemplateDuringLiquidMigration() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        { "inkstead": { "version": "1.2.0" }, "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" } }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "<h1>{{ site.title }}</h1>".write(to: root.url.appendingPathComponent("theme/home.liquid"), atomically: true, encoding: .utf8)
        try "<h1>{site.title}</h1>".write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))

        XCTAssertTrue(plan.actions.contains {
            if case .manual("theme/home.liquid", let message) = $0 {
                return message.contains("theme/home.plume already exists")
            }
            return false
        })
        XCTAssertFalse(plan.actions.contains(.delete(path: "theme/home.liquid")))
        XCTAssertFalse(plan.actions.contains {
            if case .write("theme/home.plume", _, _) = $0 { return true }
            return false
        })
    }

    func testMigratesTypeScriptConfigToVersionedJson() throws {
        let root = try TemporaryDirectory()
        try """
        import { defineConfig } from "inkstead";

        export default defineConfig({
          site: { title: "My Website", url: "https://example.com", author: "Your Name" },
          content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
          pagination: { postsPerPage: 10 }
        });
        """.write(to: root.url.appendingPathComponent("site.config.ts"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        let plan = try MigrationPlanner.plan(root: root.url, config: config)

        XCTAssertTrue(plan.actions.contains {
            if case .write("inkstead-writer.json", let content, "migrate TypeScript config to versioned JSON") = $0 {
                return content.contains(#""version" : "2.0.0""#)
            }
            return false
        })
        XCTAssertTrue(plan.actions.contains {
            if case .manual("site.config.ts", let message) = $0 {
                return message.contains("remove site.config.ts")
            }
            return false
        })

        _ = try MigrationPlanner.apply(plan, root: root.url)
        let migrated = try ConfigLoader.load(root: root.url)
        XCTAssertEqual(migrated.version, InksteadWriterMetadata.currentVersion)
        XCTAssertEqual(migrated.pagination?.postsPerPage, 10)
    }

    func testMigrationRenamesPhotosConfigToMediaConfig() throws {
        let root = try TemporaryDirectory()
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "photos": { "optimize": false, "maxWidth": 1000, "maxHeight": 900, "quality": 72 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead-writer.json"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))

        XCTAssertTrue(plan.actions.contains {
            if case .write("inkstead-writer.json", let content, "record Inkstead Writer version 2.0.0") = $0 {
                return content.contains(#""media" : {"#)
                    && content.contains(#""optimize" : false"#)
                    && !content.contains(#""photos""#)
            }
            return false
        })

        _ = try MigrationPlanner.apply(plan, root: root.url)
        let migratedSource = try String(contentsOf: root.url.appendingPathComponent("inkstead-writer.json"), encoding: .utf8)
        let migrated = try ConfigLoader.load(root: root.url)

        XCTAssertFalse(migratedSource.contains(#""photos""#))
        XCTAssertEqual(migrated.media?.optimize, false)
        XCTAssertEqual(migrated.media?.maxWidth, 1000)
    }

    func testMigrationRenamesLegacyAppSettingsToAppConnectionConfig() throws {
        let root = try TemporaryDirectory()
        try """
        {
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "writer": {
            "version": "1.2.0",
            "editor": {
              "path": "/writer",
              "provider": "github",
              "owner": "me",
              "repo": "site",
              "branch": "main",
              "categories": ["Notes", "Photos"]
            }
          }
        }
        """.write(to: root.url.appendingPathComponent("inkstead-writer.json"), atomically: true, encoding: .utf8)

        let plan = try MigrationPlanner.plan(root: root.url, config: try ConfigLoader.load(root: root.url))

        let configWrite = try XCTUnwrap(plan.actions.compactMap { action -> String? in
            if case .write("inkstead-writer.json", let content, "record Inkstead Writer version 2.0.0") = action {
                return content
            }
            return nil
        }.first)
        XCTAssertTrue(configWrite.contains(#""connection" : {"#), configWrite)
        XCTAssertTrue(configWrite.contains(#""repository" : "me\/site""#), configWrite)
        XCTAssertTrue(configWrite.contains(#""categories" : ["#), configWrite)
        XCTAssertFalse(configWrite.contains(#""writer""#), configWrite)
        XCTAssertFalse(configWrite.contains(#""editor""#), configWrite)
        XCTAssertFalse(configWrite.contains(#""path" : "/writer""#), configWrite)

        _ = try MigrationPlanner.apply(plan, root: root.url)
        let migratedSource = try String(contentsOf: root.url.appendingPathComponent("inkstead-writer.json"), encoding: .utf8)
        let migrated = try ConfigLoader.load(root: root.url)

        XCTAssertFalse(migratedSource.contains(#""editor""#))
        XCTAssertFalse(migratedSource.contains(#""writer""#))
        XCTAssertEqual(migrated.connection?.provider, .github)
        XCTAssertEqual(migrated.connection?.repository, "me/site")
        XCTAssertEqual(migrated.connection?.branch, "main")
        XCTAssertEqual(migrated.connection?.categories, ["Notes", "Photos"])
    }
}
