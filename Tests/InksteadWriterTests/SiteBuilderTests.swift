import XCTest
@testable import InksteadWriter

final class SiteBuilderTests: XCTestCase {
    func testSerializeSiteExposesOptionalThemeFields() {
        let site = SiteConfig(
            title: "My Website",
            url: "https://example.com",
            author: "Your Name",
            description: "Description",
            lang: "en",
            timezone: "Europe/London",
            email: "me@example.com",
            avatar: "/avatar.jpg",
            bio: "A short bio.",
            navigation: [NavigationItem(name: "Photos", url: "/photos/", icon: "fa-camera", className: "nav-photos")],
            social: [SocialItem(name: "Mastodon", url: "https://mastodon.example/@me", relMe: true, icon: "fa-mastodon", className: "social-mastodon")]
        )

        let serialized = serializeSite(site)
        let navigation = serialized["navigation"] as? [[String: Any]]
        let social = serialized["social"] as? [[String: Any]]

        XCTAssertEqual(serialized["bio"] as? String, "A short bio.")
        XCTAssertEqual(serialized["timezone"] as? String, "Europe/London")
        XCTAssertEqual(serialized["email"] as? String, "me@example.com")
        XCTAssertEqual(navigation?.first?["icon"] as? String, "fa-camera")
        XCTAssertEqual(navigation?.first?["className"] as? String, "nav-photos")
        XCTAssertEqual(social?.first?["icon"] as? String, "fa-mastodon")
        XCTAssertEqual(social?.first?["className"] as? String, "social-mastodon")
        XCTAssertEqual(social?.first?["relMe"] as? Bool, true)
    }

    func testBuildsStaticOutputWithPlumeTemplates() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": {
            "title": "My Website",
            "url": "https://example.com",
            "author": "Your Name",
            "description": "Notes and photos.",
            "avatar": "/favicon.png",
            "social": [{ "name": "Me", "url": "https://bsky.app/profile/example.com", "relMe": true }]
          },
          "content": { "posts": "content/posts", "pages": "content/pages", "media": "content/media" },
          "pagination": { "postsPerPage": 2 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        ---
        title: "Why I Still Want a Personal Website"
        date: 2026-05-10T18:30:00+01:00
        categories:
          - Essays
        ---

        Longer article content here.
        """.write(to: root.url.appendingPathComponent("content/posts/first-article.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: About
        ---

        This is my website.
        """.write(to: root.url.appendingPathComponent("content/pages/about.md"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        try SiteBuilder.build(root: root.url, config: config)

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        let post = try String(contentsOf: root.url.appendingPathComponent("dist/2026/05/10/first-article/index.html"), encoding: .utf8)
        let category = try String(contentsOf: root.url.appendingPathComponent("dist/categories/essays/index.html"), encoding: .utf8)

        XCTAssertTrue(home.contains("Why I Still Want a Personal Website"))
        XCTAssertTrue(home.contains(#"<link rel="icon" href="/favicon.png">"#))
        XCTAssertTrue(home.contains(#"<link rel="me" href="https://bsky.app/profile/example.com">"#))
        XCTAssertTrue(home.contains(#"<link rel="stylesheet" href="/assets/plume/sitestyles-"#))
        let css = try FileManager.default.contentsOfDirectory(at: root.url.appendingPathComponent("dist/assets/plume"), includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertTrue(post.contains("Longer article content here."))
        XCTAssertTrue(category.contains("#Essays"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/feed.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/feed.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/sitemap.xml").path))
    }

    func testBuildWritesDefaultAndCustomNotFoundPage() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        try SiteBuilder.build(root: root.url, config: config)

        let defaultNotFound = try String(contentsOf: root.url.appendingPathComponent("dist/404.html"), encoding: .utf8)
        XCTAssertTrue(defaultNotFound.contains("Page not found"))
        XCTAssertTrue(defaultNotFound.contains("Return home"))

        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/pages"), withIntermediateDirectories: true)
        try """
        <section class="custom-404">
          <h1>{notFound.title}</h1>
          <p>Custom missing page</p>
        </section>
        """.write(to: root.url.appendingPathComponent("theme/pages/404.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: config)

        let customNotFound = try String(contentsOf: root.url.appendingPathComponent("dist/404.html"), encoding: .utf8)
        XCTAssertTrue(customNotFound.contains(#"class="custom-404""#))
        XCTAssertTrue(customNotFound.contains("Custom missing page"))
    }

    func testCanHidePoweredByFooterLink() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "theme": { "showPoweredBy": false }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        try SiteBuilder.build(root: root.url, config: config)

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertFalse(home.contains("Powered by"))
    }

    func testBuildRejectsLegacyLiquidTemplatesAndPointsToUpgrade() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "Legacy".write(to: root.url.appendingPathComponent("theme/home.liquid"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))) { error in
            XCTAssertTrue(String(describing: error).contains("Run ./inkstead-writer migrate"))
        }
    }

    func testAssetPassthroughToOutputRootMergesWithoutDeletingBuiltPages() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("public/assets"), withIntermediateDirectories: true)
        try "body{}".write(to: root.url.appendingPathComponent("public/assets/theme.css"), atomically: true, encoding: .utf8)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "assets": { "passthrough": [{ "from": "public", "to": "." }] }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        try SiteBuilder.build(root: root.url, config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/index.html").path))
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("dist/assets/theme.css"), encoding: .utf8), "body{}")
    }

    func testPlumeAssetAndImageHelpersFingerprintThemeAssets() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/images"), withIntermediateDirectories: true)
        try testPNGData(width: 32, height: 18).write(to: root.url.appendingPathComponent("theme/images/avatar.png"))
        try testPNGData(width: 20, height: 10).write(to: root.url.appendingPathComponent("content/media/photo.png"))
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <html>
        <head><title>{meta.title}</title></head>
        <body>{content}</body>
        </html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        <a href="{asset("images/avatar.png")}">Avatar</a>
        <a href="{asset("/media/photo.png")}">Media</a>
        <a href="{asset("photo.png")}">Media by name</a>
        @image("images/avatar.png", alt: "Avatar", class: "avatar", sizes: "32px")
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains(#"href="/assets/plume/avatar-"#))
        XCTAssertTrue(home.contains(#"href="/media/photo.png""#))
        XCTAssertTrue(home.contains(#"<img src="/assets/plume/avatar-"#))
        XCTAssertTrue(home.contains(#"alt="Avatar""#))
        XCTAssertTrue(home.contains(#"class="avatar""#))
        XCTAssertTrue(home.contains(#"sizes="32px""#))
        XCTAssertTrue(home.contains(#"width="32""#))
        XCTAssertTrue(home.contains(#"height="18""#))
        XCTAssertTrue(home.contains(#"loading="lazy""#))
        XCTAssertTrue(home.contains(#"decoding="async""#))
        let plumeAssets = try FileManager.default.contentsOfDirectory(at: root.url.appendingPathComponent("dist/assets/plume"), includingPropertiesForKeys: nil)
        XCTAssertEqual(plumeAssets.filter { $0.lastPathComponent.hasPrefix("avatar-") && $0.pathExtension == "png" }.count, 1)
    }

    func testPlumeImageHelperEmitsResponsiveSrcsetVariants() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/images"), withIntermediateDirectories: true)
        try testPNGData(width: 64, height: 32).write(to: root.url.appendingPathComponent("theme/images/hero.png"))
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <html>
        <head><title>{meta.title}</title></head>
        <body>{content}</body>
        </html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        @image("images/hero.png", alt: "Hero", widths: [16, 32, 128], sizes: "(min-width: 720px) 640px, 100vw")
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains(#"<img src="/assets/plume/hero-"#))
        XCTAssertTrue(home.contains(#"srcset="/assets/plume/hero-16w-"#))
        XCTAssertTrue(home.contains(" 16w, /assets/plume/hero-32w-"))
        XCTAssertTrue(home.contains(" 32w, /assets/plume/hero-64w-"))
        XCTAssertTrue(home.contains(#" 64w""#))
        XCTAssertTrue(home.contains(#"sizes="(min-width: 720px) 640px, 100vw""#))
        let plumeAssets = try FileManager.default.contentsOfDirectory(at: root.url.appendingPathComponent("dist/assets/plume"), includingPropertiesForKeys: nil)
        XCTAssertEqual(plumeAssets.filter { $0.lastPathComponent.hasPrefix("hero-") && $0.pathExtension == "png" }.count, 4)
        XCTAssertTrue(plumeAssets.contains { $0.lastPathComponent.hasPrefix("hero-16w-") })
        XCTAssertTrue(plumeAssets.contains { $0.lastPathComponent.hasPrefix("hero-32w-") })
        XCTAssertTrue(plumeAssets.contains { $0.lastPathComponent.hasPrefix("hero-64w-") })
    }

    func testPlumeAssetHelperRejectsMissingMediaReferences() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <html><body>{content}</body></html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        <a href="{asset("/media/missing.png")}">Missing</a>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))) { error in
            XCTAssertTrue(String(describing: error).contains("Plume asset /media/missing.png was not found"))
        }
    }

    func testBuildExposesDataSourcesAndCustomCollectionsToPlume() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/collections/books"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("data"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try Data(#"[{"name":"Inkstead","url":"https://example.com/inkstead"}]"#.utf8).write(to: root.url.appendingPathComponent("data/repos.json"))
        try """
        ---
        title: Second Book
        author: B
        order: 2
        ---

        Later book.
        """.write(to: root.url.appendingPathComponent("content/collections/books/second.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: First Book
        author: A
        order: 1
        ---

        Earlier book.
        """.write(to: root.url.appendingPathComponent("content/collections/books/first.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Draft Book
        status: draft
        ---

        Hidden book.
        """.write(to: root.url.appendingPathComponent("content/collections/books/draft.md"), atomically: true, encoding: .utf8)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "data": { "repos": { "file": "data/repos.json" } }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <html><body>{content}</body></html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        <section class="repos">
        @for repo in data.repos {
          <a href="{repo.url}">{repo.name}</a>
        }
        </section>
        <section class="books">
        @for book in collections.books {
          <article data-slug="{book.slug}"><h2>{book.title}</h2><p>{book.author}</p>{book.content}</article>
        }
        </section>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains(#"<a href="https://example.com/inkstead">Inkstead</a>"#))
        XCTAssertTrue(home.contains(#"data-slug="first""#))
        XCTAssertTrue(home.contains("<h2>First Book</h2>"))
        XCTAssertTrue(home.contains("<p>Earlier book.</p>"))
        XCTAssertTrue(home.contains(#"data-slug="second""#))
        XCTAssertFalse(home.contains("Draft Book"))
        XCTAssertLessThan(try XCTUnwrap(home.range(of: "First Book")?.lowerBound), try XCTUnwrap(home.range(of: "Second Book")?.lowerBound))
    }

    func testBuildSupportsCustomOutputRawHtmlHardBreaksAndPagination() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("public/assets"), withIntermediateDirectories: true)
        try "body{}".write(to: root.url.appendingPathComponent("public/assets/theme.css"), atomically: true, encoding: .utf8)
        try """
        ---
        title: About
        ---

        This is my website.
        """.write(to: root.url.appendingPathComponent("content/pages/about.md"), atomically: true, encoding: .utf8)
        for day in 10...12 {
            try """
            ---
            date: 2026-05-\(day)T18:30:00+01:00
            ---

            <p>Raw \(day)</p>

            Line one
            Line two
            """.write(to: root.url.appendingPathComponent("content/posts/2026-05-\(day)-extra-\(day).md"), atomically: true, encoding: .utf8)
        }
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": {
            "title": "My Website",
            "url": "https://example.com",
            "author": "Your Name",
            "description": "Desc",
            "social": [{ "name": "Me", "url": "https://bsky.app/profile/example.com" }]
          },
          "content": { "posts": "content/posts", "pages": "content/pages", "media": "content/media" },
          "build": { "output": "build" },
          "markdown": { "html": true, "breaks": true },
          "assets": { "passthrough": [{ "from": "public", "to": "." }] },
          "pagination": { "postsPerPage": 2 },
          "feeds": { "limit": 2 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let html = try String(contentsOf: root.url.appendingPathComponent("build/index.html"), encoding: .utf8)
        let page2 = try String(contentsOf: root.url.appendingPathComponent("build/page/2/index.html"), encoding: .utf8)
        let feed = try String(contentsOf: root.url.appendingPathComponent("build/feed.json"), encoding: .utf8)
        let post = try String(contentsOf: root.url.appendingPathComponent("build/2026/05/12/extra-12/index.html"), encoding: .utf8)
        let about = try String(contentsOf: root.url.appendingPathComponent("build/about/index.html"), encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("build/assets/theme.css").path))
        XCTAssertTrue(html.contains("h-entry"))
        XCTAssertTrue(html.contains(#"rel="me""#))
        XCTAssertTrue(page2.contains("h-entry"))
        XCTAssertEqual(feed.components(separatedBy: "content_html").count - 1, 2)
        XCTAssertTrue(post.contains("<p>Raw 12</p>"))
        XCTAssertTrue(post.contains("<br>"))
        XCTAssertTrue(post.contains(#"<meta name="description" content="Raw 12 Line one Line two">"#))
        XCTAssertFalse(post.contains(#"<meta name="description" content="Desc">"#))
        XCTAssertTrue(about.contains(#"<meta name="description" content="This is my website.">"#))
        XCTAssertFalse(about.contains(#"<meta name="description" content="Desc">"#))
    }

    func testFeedsUseCurrentShapeAndConfiguredLimit() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        for day in 1...3 {
            try """
            ---
            title: Post \(day)
            date: 2026-01-0\(day)T12:00:00+00:00
            lastmod: 2026-02-0\(day)T12:00:00+00:00
            ---

            Body \(day)
            """.write(to: root.url.appendingPathComponent("content/posts/2026-01-0\(day)-post-\(day).md"), atomically: true, encoding: .utf8)
        }
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name", "description": "Desc" },
          "feeds": { "limit": 2 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        try SiteBuilder.build(root: root.url, config: config)

        let rss = try String(contentsOf: root.url.appendingPathComponent("dist/feed.xml"), encoding: .utf8)
        XCTAssertTrue(rss.hasPrefix("<?xml"))
        XCTAssertTrue(rss.contains(#"xmlns:content="http://purl.org/rss/1.0/modules/content/""#))
        XCTAssertTrue(rss.contains(#"<atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>"#))
        XCTAssertFalse(rss.contains(#"<script xmlns="http://www.w3.org/1999/xhtml""#))
        XCTAssertTrue(rss.contains("<content:encoded><![CDATA[<p>Body 3</p>"))
        XCTAssertFalse(rss.contains("Post 1"))

        let jsonData = try Data(contentsOf: root.url.appendingPathComponent("dist/feed.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let authors = try XCTUnwrap(json["authors"] as? [[String: Any]])
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertEqual(authors.first?["name"] as? String, "Your Name")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?["title"] as? String, "Post 3")
        XCTAssertEqual(items.first?["content_text"] as? String, "Body 3")
        XCTAssertEqual(items.first?["date_modified"] as? String, "2026-02-03T12:00:00Z")
    }

    func testBuildInjectsConventionalFeedPresentationTemplate() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Feed Post
        date: 2026-01-03T12:00:00+00:00
        categories:
          - Notes
        ---

        Feed body
        """.write(to: root.url.appendingPathComponent("content/posts/post.md"), atomically: true, encoding: .utf8)
        try """
        @style {
          .feed-custom { color: rebeccapurple; }
        }
        @script(language: "javascript") {
          window.__feedPresented = true;
        }
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom"><channel><title>{feed.title}</title><link>{feed.siteUrl}</link><description>{feed.description}</description><atom:link href="{feed.url}" rel="self" type="application/rss+xml"/>
        @if feed.presentationScriptSrc {
        <script xmlns="http://www.w3.org/1999/xhtml" src="{feed.presentationScriptSrc}"></script>
        }
        @for item in feed.items {
        <item>@if item.title {<title>{item.title}</title>}<link>{item.url}</link><guid>{item.guid}</guid><pubDate>{item.pubDate}</pubDate><description><![CDATA[{item.html | raw}]]></description><content:encoded><![CDATA[{item.html | raw}]]></content:encoded></item>
        }
        </channel></rss>
        """.write(to: root.url.appendingPathComponent("theme/feed.xml.plume"), atomically: true, encoding: .utf8)
        try """
        {
          "custom": true,
          "title": {feed.title | json},
          "category": {feed.category.name | default("") | json},
          "count": {feed.items.size}
        }
        """.write(to: root.url.appendingPathComponent("theme/feed.json.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let rss = try String(contentsOf: root.url.appendingPathComponent("dist/feed.xml"), encoding: .utf8)
        let mainJSONData = try Data(contentsOf: root.url.appendingPathComponent("dist/feed.json"))
        let mainJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: mainJSONData) as? [String: Any])
        let categoryRss = try String(contentsOf: root.url.appendingPathComponent("dist/categories/notes/feed.xml"), encoding: .utf8)
        let categoryJSONData = try Data(contentsOf: root.url.appendingPathComponent("dist/categories/notes/feed.json"))
        let categoryJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: categoryJSONData) as? [String: Any])
        XCTAssertTrue(rss.hasPrefix("<?xml"))
        XCTAssertTrue(categoryRss.hasPrefix("<?xml"))
        XCTAssertTrue(rss.contains(#"<script xmlns="http://www.w3.org/1999/xhtml" src="/assets/plume/feed-"#))
        XCTAssertTrue(categoryRss.contains(#"<script xmlns="http://www.w3.org/1999/xhtml" src="/assets/plume/feed-"#))
        XCTAssertEqual(mainJSON["custom"] as? Bool, true)
        XCTAssertEqual(mainJSON["category"] as? String, "")
        XCTAssertEqual(categoryJSON["title"] as? String, "My Website - Notes")
        XCTAssertEqual(categoryJSON["category"] as? String, "Notes")

        let plumeAssets = try FileManager.default.contentsOfDirectory(at: root.url.appendingPathComponent("dist/assets/plume"), includingPropertiesForKeys: nil)
        let css = try plumeAssets
            .filter { $0.pathExtension == "css" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let js = try plumeAssets
            .filter { $0.pathExtension == "js" && $0.lastPathComponent.hasPrefix("feed-") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(css.contains(".feed-custom { color: rebeccapurple; }"))
        XCTAssertTrue(js.contains("window.PlumeFeed"))
        XCTAssertTrue(js.contains(#"/assets/plume/feed-"#) || js.contains(#"\/assets\/plume\/feed-"#))
        XCTAssertTrue(js.contains(".css"))
        XCTAssertTrue(js.contains("window.__feedPresented = true;"))
    }

    func testFeedTemplateRejectsRuntimeActions() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        @state open = false
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>{feed.title}</title></channel></rss>
        """.write(to: root.url.appendingPathComponent("theme/feed.xml.plume"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))) { error in
            XCTAssertTrue(String(describing: error).contains("feed.xml.plume renders RSS XML"))
        }
    }

    func testBuildsCategoryPagesDraftExclusionAndCustomPlumeThemes() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts/essays"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "pagination": { "postsPerPage": 2 },
          "syndication": { "providers": ["mastodon"] }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        for day in 10...12 {
            try """
            ---
            title: Category \(day)
            date: 2026-06-\(day)T18:30:00+01:00
            categories:
              - Photography
            ---

            Post \(day).
            """.write(to: root.url.appendingPathComponent("content/posts/2026-06-\(day)-category-\(day).md"), atomically: true, encoding: .utf8)
        }
        try """
        ---
        title: Directory Category
        date: 2026-08-10T18:30:00+01:00
        categories:
          - essays
        ---

        From a folder.
        """.write(to: root.url.appendingPathComponent("content/posts/essays/2026-08-10-directory-category.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Hidden Draft
        date: 2026-09-21T18:30:00+01:00
        status: draft
        syndicate:
          - mastodon
        ---

        Should stay private.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-09-21-draft.md"), atomically: true, encoding: .utf8)
        try """
        <h1>Start Here</h1>
        <ul>@for category in categories {<li><a href="{category.urlPath}">{category.name}</a></li>}</ul>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        let photography = try String(contentsOf: root.url.appendingPathComponent("dist/categories/photography/index.html"), encoding: .utf8)
        let photographyPage2 = try String(contentsOf: root.url.appendingPathComponent("dist/categories/photography/page/2/index.html"), encoding: .utf8)
        let photographyFeed = try String(contentsOf: root.url.appendingPathComponent("dist/categories/photography/feed.xml"), encoding: .utf8)
        let photographyJSONFeed = try Data(contentsOf: root.url.appendingPathComponent("dist/categories/photography/feed.json"))
        let photographyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: photographyJSONFeed) as? [String: Any])
        let essays = try String(contentsOf: root.url.appendingPathComponent("dist/categories/essays/index.html"), encoding: .utf8)
        let sitemap = try String(contentsOf: root.url.appendingPathComponent("dist/sitemap.xml"), encoding: .utf8)

        XCTAssertTrue(home.contains("Start Here"))
        XCTAssertTrue(home.contains("/categories/photography/"))
        XCTAssertFalse(home.contains("Category 12"))
        XCTAssertTrue(photography.contains("#Photography"))
        XCTAssertTrue(photography.contains(#"href="/categories/photography/feed.xml""#))
        XCTAssertTrue(photography.contains(#"href="/categories/photography/feed.json""#))
        XCTAssertTrue(photographyPage2.contains("h-entry"))
        XCTAssertTrue(photographyFeed.contains("My Website - Photography"))
        XCTAssertEqual(photographyJSON["title"] as? String, "My Website - Photography")
        XCTAssertTrue(essays.contains("Directory Category"))
        XCTAssertFalse(essays.contains("essays\n          - essays"))
        XCTAssertFalse(sitemap.contains("draft"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/2026/09/21/draft/index.html").path))
    }

    func testBuildSupportsThemePackageShapeComponentsAndSafeHTML() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/layouts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/components"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Component Post
        date: 2026-05-10T18:30:00+01:00
        ---

        Body with **HTML**.
        """.write(to: root.url.appendingPathComponent("content/posts/component.md"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <main>{content}</main>
        """.write(to: root.url.appendingPathComponent("theme/layouts/default.plume"), atomically: true, encoding: .utf8)
        try """
        @component PostCard(post) {
        <article class="post-card" class+="{post.kind}">
          <h2>{post.title}</h2>
          {slot}
        </article>
        }
        """.write(to: root.url.appendingPathComponent("theme/components/PostCard.plume"), atomically: true, encoding: .utf8)
        try """
        @for post in posts {
        @PostCard(post) {
          {post.html}
        }
        }
        """.write(to: root.url.appendingPathComponent("theme/pages/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        let articleClass = try XCTUnwrap(firstCapture(in: home, pattern: #"<article[^>]*class="([^"]*)""#))
        XCTAssertTrue(Set(articleClass.split(separator: " ").map(String.init)).isSuperset(of: ["post-card", "article"]))
        XCTAssertTrue(home.contains("<strong>HTML</strong>"))
        XCTAssertFalse(home.contains("&lt;strong&gt;HTML&lt;/strong&gt;"))
    }

    func testOrganizedThemeTemplatesTakePriorityOverFlatFallbacks() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/layouts"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <main>Flat layout {content}</main>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        <!doctype html>
        <main>Organized layout {content}</main>
        """.write(to: root.url.appendingPathComponent("theme/layouts/default.plume"), atomically: true, encoding: .utf8)
        try "<p>Flat home</p>".write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)
        try "<p>Organized home</p>".write(to: root.url.appendingPathComponent("theme/pages/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains("Organized layout"))
        XCTAssertTrue(home.contains("Organized home"))
        XCTAssertFalse(home.contains("Flat layout"))
        XCTAssertFalse(home.contains("Flat home"))
    }

    func testBuildEmitsPlumeRuntimeWhenTemplatesUseState() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        @state open = false
        <button on:click="{open.toggle()}" aria-expanded="{open}">{open ? "Close" : "Open"}</button>
        <p hidden?="{!open}">Hello</p>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains("data-plume-state"))
        XCTAssertTrue(home.contains(#""open":false"#))
        XCTAssertTrue(home.contains(#"<script src="/assets/plume-runtime.js" defer></script>"#))
        XCTAssertTrue(home.contains(#"data-plume-on-click="open.toggle()""#))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/assets/plume-runtime.js").path))
        let runtime = try String(contentsOf: root.url.appendingPathComponent("dist/assets/plume-runtime.js"), encoding: .utf8)
        XCTAssertFalse(runtime.contains("@browserRuntime"))
        XCTAssertFalse(runtime.contains("=>"))
        XCTAssertTrue(runtime.contains("function bootPlumeRuntime()"))
    }

    func testBuildEmitsPlumeRuntimeForBrowserActionsWithoutState() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        <button on:click="{page.scrollToTop(smooth: true)}">Top</button>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains("data-plume-state"))
        XCTAssertTrue(home.contains(#"{}"#))
        XCTAssertTrue(home.contains(#"<script src="/assets/plume-runtime.js" defer></script>"#))
        XCTAssertTrue(home.contains(#"data-plume-on-click="page.scrollToTop(smooth: true)""#))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/assets/plume-runtime.js").path))
    }

    func testBuildEmitsPlumeRuntimeForMeasurementAndViewportActions() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        @state sliderX = 0
        @state sliderWidth = 0
        <nav on:resize="{page.measure('.active', into: ['sliderX', 'sliderWidth'])}">
          <a class="active" on:pointerenter="{page.measure(event.target, into: ['sliderX', 'sliderWidth'], round: true)}">Home</a>
          <span style:--slider-x="{sliderX}px" style:--slider-width="{sliderWidth}px"></span>
        </nav>
        <section on:visible="{sliderX.set(10)}">Intro</section>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains(#"data-plume-on-resize="page.measure('.active', into: ['sliderX', 'sliderWidth'])""#))
        XCTAssertTrue(home.contains(#"data-plume-style-template---slider-x="{sliderX}px""#))
        XCTAssertTrue(home.contains(#"data-plume-on-visible="sliderX.set(10)""#))
        let runtime = try String(contentsOf: root.url.appendingPathComponent("dist/assets/plume-runtime.js"), encoding: .utf8)
        XCTAssertFalse(runtime.contains("=>"))
        XCTAssertTrue(runtime.contains("getBoundingClientRect"))
        XCTAssertTrue(runtime.contains("IntersectionObserver"))
        XCTAssertTrue(runtime.contains(#"data-plume-on-visible"#))
    }

    func testBuildInjectsDeclarativeNavigationRuntimeConfig() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        @navigation(root: "main", viewTransitions: true, scroll: "top", minimumDuration: 250) {
          on:beforeSwap {
            page.addClass("is-leaving")
          }
          on:afterSwap {
            page.removeClass("is-leaving")
          }
        }
        <!doctype html>
        <html><head><title>{meta.title}</title></head><body><main>{content}</main></body></html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        <h1>{title}</h1>
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains("data-plume-navigation"))
        XCTAssertTrue(home.contains(#""root":"main""#))
        XCTAssertTrue(home.contains(#""minimumDuration":250"#))
        XCTAssertTrue(home.contains(#""beforeSwap":["page.addClass(\"is-leaving\")"]"#))
        XCTAssertTrue(home.contains(#""afterSwap":["page.removeClass(\"is-leaving\")"]"#))
        XCTAssertTrue(home.contains(#"<script src="/assets/plume-runtime.js" defer></script>"#))
        let runtime = try String(contentsOf: root.url.appendingPathComponent("dist/assets/plume-runtime.js"), encoding: .utf8)
        XCTAssertTrue(runtime.contains("plume:navigate:${navigationEventName(name)}"))
        XCTAssertTrue(runtime.contains("document.startViewTransition"))
        XCTAssertTrue(runtime.contains("navigation.minimumDuration"))
        XCTAssertTrue(runtime.contains(#"extension !== "html" && extension !== "htm""#))
    }

    func testBuildExtractsInlineFileAndScopedPlumeStylesAndScripts() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/styles"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/components"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try ".from-file { color: blue; }".write(to: root.url.appendingPathComponent("theme/styles/site.css"), atomically: true, encoding: .utf8)
        try #"document.documentElement.dataset.fromFile = "true";"#.write(to: root.url.appendingPathComponent("theme/scripts/site.js"), atomically: true, encoding: .utf8)
        try """
        let header = page.query("#site-header")
        on page.scroll {
          header.toggleClass("is-scrolled", when: page.scrollY > 24)
        }
        """.write(to: root.url.appendingPathComponent("theme/scripts/client.plume"), atomically: true, encoding: .utf8)
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
        @style {
          .from-layout { color: red; }
        }
        <!doctype html>
        <html>
        <head><title>{meta.title}</title></head>
        <body>{content}</body>
        </html>
        """.write(to: root.url.appendingPathComponent("theme/layout.plume"), atomically: true, encoding: .utf8)
        try """
        @component Card(title) {
          @style(scoped: true) {
            .card { display: grid; }
            .card img:hover { opacity: 0.8; }
            @media (min-width: 40rem) {
              .card { grid-template-columns: 1fr 1fr; }
            }
          }
          @script(scoped: true, language: "javascript") {
            root.dataset.card = "ready";
          }
          <article class="card"><h1>{title}</h1><img src="/media/photo.jpg" alt=""></article>
        }
        """.write(to: root.url.appendingPathComponent("theme/components/Card.plume"), atomically: true, encoding: .utf8)
        try """
        @Card(title)
        """.write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))

        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains(#"<link rel="stylesheet" href="/assets/plume/site-"#))
        XCTAssertTrue(home.contains(#"<link rel="stylesheet" href="/assets/plume/layout-"#))
        XCTAssertTrue(home.contains(#"<link rel="stylesheet" href="/assets/plume/card-"#))
        XCTAssertTrue(home.contains(#"<script type="module" src="/assets/plume/site-"#))
        XCTAssertTrue(home.contains(#"<script type="module" src="/assets/plume/card-"#))
        XCTAssertTrue(home.contains("data-plume-scope-plume-"))

        let plumeAssetsDir = root.url.appendingPathComponent("dist/assets/plume")
        let plumeAssets = try FileManager.default.contentsOfDirectory(at: plumeAssetsDir, includingPropertiesForKeys: nil)
        let css = try plumeAssets
            .filter { $0.pathExtension == "css" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(css.contains(".from-file { color: blue; }"))
        XCTAssertTrue(css.contains(".from-layout { color: red; }"))
        XCTAssertTrue(css.contains(".card[data-plume-scope-plume-"))
        XCTAssertTrue(css.contains("img[data-plume-scope-plume-"))
        XCTAssertTrue(css.contains("@media (min-width: 40rem)"))
        let js = try plumeAssets
            .filter { $0.pathExtension == "js" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(js.contains(#"document.documentElement.dataset.fromFile = "true";"#))
        XCTAssertTrue(js.contains(##"const header = document.querySelector("#site-header");"##))
        XCTAssertTrue(js.contains(#"(header)?.classList.toggle("is-scrolled", !!(window.scrollY > 24));"#))
        XCTAssertTrue(js.contains(##"const menu = document.querySelector("#menu");"##))
        XCTAssertTrue(js.contains(#"document.querySelectorAll(".toggle")"#))
        XCTAssertTrue(js.contains(#"(menu)?.classList.toggle("is-open");"#))
        XCTAssertTrue(js.contains(#"let selector = "[data-plume-scope-plume-"#))
        XCTAssertTrue(js.contains("async function(root)"))
        XCTAssertTrue(js.contains(#"root.dataset.card = "ready";"#))
    }

    func testSummaryMoreCommentsAndPhotoPostCollections() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Summary Post
        date: 2026-09-10T18:30:00+01:00
        summary: Custom summary wins.
        ---

        Body should not be the excerpt.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-09-10-summary.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: More Post
        date: 2026-09-11T18:30:00+01:00
        ---

        Intro [paragraph](https://example.com).

        <!--more-->

        Rest of the article.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-09-11-more.md"), atomically: true, encoding: .utf8)
        try """
        ---
        date: 2026-10-01T18:30:00+01:00
        ---

        ![](/media/camera.jpg)
        """.write(to: root.url.appendingPathComponent("content/posts/2026-10-01-photo.md"), atomically: true, encoding: .utf8)
        try """
        ---
        date: 2026-10-02T18:30:00+01:00
        ---

        ![](/media/screenshot.png)
        """.write(to: root.url.appendingPathComponent("content/posts/2026-10-02-screenshot.md"), atomically: true, encoding: .utf8)
        try #"<ul>@for post in photoPosts {<li>{post.firstImage}</li>}</ul>"#
            .write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        let posts = try ContentLoader.loadPosts(root: root.url, config: config)
        let summary = try XCTUnwrap(posts.first { $0.title == "Summary Post" })
        let more = try XCTUnwrap(posts.first { $0.title == "More Post" })

        XCTAssertEqual(summary.excerpt, "<p>Custom summary wins.</p>\n")
        XCTAssertTrue(summary.hasMore)
        XCTAssertEqual(more.excerpt, #"<p>Intro <a href="https://example.com">paragraph</a>.</p>"# + "\n")
        XCTAssertTrue(more.hasMore)

        try SiteBuilder.build(root: root.url, config: config)
        let home = try String(contentsOf: root.url.appendingPathComponent("dist/index.html"), encoding: .utf8)
        XCTAssertTrue(home.contains("/media/camera.jpg"))
        XCTAssertFalse(home.contains("/media/screenshot.png"))
    }

    func testOptimizesContentPhotosDuringBuild() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        let source = root.url.appendingPathComponent("content/media/large.jpg")
        try testJPEGData(width: 200, height: 150).write(to: source)
        let pngSource = root.url.appendingPathComponent("content/media/large.png")
        try testPNGData(width: 200, height: 150).write(to: pngSource)
        let webpSource = root.url.appendingPathComponent("content/media/large.webp")
        try testWebPData(width: 200, height: 150).write(to: webpSource)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "media": { "maxWidth": 100, "maxHeight": 100, "quality": 76 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        let originalDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: Data(contentsOf: source), mimeType: "image/jpeg"))
        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))
        let optimized = try Data(contentsOf: root.url.appendingPathComponent("dist/media/large.jpg"))
        let optimizedDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: optimized, mimeType: "image/jpeg"))
        let optimizedPNG = try Data(contentsOf: root.url.appendingPathComponent("dist/media/large.png"))
        let optimizedPNGDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: optimizedPNG, mimeType: "image/png"))
        let optimizedWebP = try Data(contentsOf: root.url.appendingPathComponent("dist/media/large.webp"))
        let optimizedWebPDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: optimizedWebP, mimeType: "image/webp"))

        XCTAssertEqual(originalDimensions.width, 200)
        XCTAssertEqual(originalDimensions.height, 150)
        XCTAssertEqual(optimizedDimensions.width, 100)
        XCTAssertEqual(optimizedDimensions.height, 75)
        XCTAssertEqual(optimizedPNGDimensions.width, 100)
        XCTAssertEqual(optimizedPNGDimensions.height, 75)
        XCTAssertEqual(optimizedWebPDimensions.width, 100)
        XCTAssertEqual(optimizedWebPDimensions.height, 75)
    }

    func testCanDisableContentPhotoOptimization() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        let source = root.url.appendingPathComponent("content/media/large.jpg")
        try testJPEGData(width: 200, height: 150).write(to: source)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "media": { "optimize": false, "maxWidth": 100, "maxHeight": 100 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))
        let copied = try Data(contentsOf: root.url.appendingPathComponent("dist/media/large.jpg"))
        let copiedDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: copied, mimeType: "image/jpeg"))

        XCTAssertEqual(copiedDimensions.width, 200)
        XCTAssertEqual(copiedDimensions.height, 150)
    }

    func testLeavesPassthroughImagesUnoptimized() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("public/assets"), withIntermediateDirectories: true)
        let source = root.url.appendingPathComponent("public/assets/large.jpg")
        try testJPEGData(width: 200, height: 150).write(to: source)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "assets": { "passthrough": [{ "from": "public", "to": "." }] },
          "media": { "maxWidth": 100, "maxHeight": 100 }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)

        try SiteBuilder.build(root: root.url, config: try ConfigLoader.load(root: root.url))
        let copied = try Data(contentsOf: root.url.appendingPathComponent("dist/assets/large.jpg"))
        let copiedDimensions = try XCTUnwrap(SyndicationMedia.dimensions(bytes: copied, mimeType: "image/jpeg"))

        XCTAssertEqual(copiedDimensions.width, 200)
        XCTAssertEqual(copiedDimensions.height, 150)
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
