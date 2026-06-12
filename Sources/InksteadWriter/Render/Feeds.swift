import Foundation

public enum FeedRenderer {
    public static func rssContext(
        config: InksteadWriterConfig,
        posts: [NormalizedPost],
        title: String? = nil,
        path: String = "/feed.xml",
        presentationScriptSrc: String = "",
        presentationStyleHrefs: [String] = [],
        category: [String: Any]? = nil
    ) -> [String: Any] {
        let feedTitle = title ?? config.site.title
        let feedPath = path.hasPrefix("/") ? path : "/\(path)"
        let siteUrl = cleanBaseUrl(config.site.url)
        return [
            "format": "xml",
            "title": feedTitle,
            "url": siteUrl + feedPath,
            "path": feedPath,
            "siteUrl": config.site.url,
            "homePageUrl": "\(siteUrl)/",
            "description": config.site.description ?? config.site.title,
            "presentationScriptSrc": presentationScriptSrc,
            "presentationStyleHrefs": presentationStyleHrefs,
            "category": category ?? NSNull(),
            "items": limitedPosts(config: config, posts: posts).map { post in
                [
                    "title": post.title ?? "",
                    "url": post.canonicalUrl,
                    "guid": post.canonicalUrl,
                    "pubDate": rfc822(post.date),
                    "html": post.html
                ]
            }
        ]
    }

    public static func jsonContext(
        config: InksteadWriterConfig,
        posts: [NormalizedPost],
        title: String? = nil,
        path: String = "/feed.json",
        category: [String: Any]? = nil
    ) -> [String: Any] {
        let feedTitle = title ?? config.site.title
        let feedPath = path.hasPrefix("/") ? path : "/\(path)"
        let siteUrl = cleanBaseUrl(config.site.url)
        return [
            "format": "json",
            "version": "https://jsonfeed.org/version/1.1",
            "title": feedTitle,
            "url": siteUrl + feedPath,
            "path": feedPath,
            "siteUrl": config.site.url,
            "homePageUrl": "\(siteUrl)/",
            "description": config.site.description ?? "",
            "category": category ?? NSNull(),
            "items": limitedPosts(config: config, posts: posts).enumerated().map { index, post in
                [
                    "comma": index == 0 ? "" : ",",
                    "id": post.canonicalUrl,
                    "url": post.canonicalUrl,
                    "title": post.title ?? "",
                    "contentHTML": post.html,
                    "contentText": plainText(post.html),
                    "datePublished": iso(post.date),
                    "dateModified": iso(post.lastmod ?? post.date)
                ]
            }
        ]
    }

    public static func rss(
        config: InksteadWriterConfig,
        posts: [NormalizedPost],
        title: String? = nil,
        path: String = "/feed.xml"
    ) -> String {
        let feedTitle = title ?? config.site.title
        let items = limitedPosts(config: config, posts: posts).map { post in
            let title = post.title.map { "<title>\(escape($0))</title>" } ?? ""
            return """
            <item>\(title)<link>\(escape(post.canonicalUrl))</link><guid>\(escape(post.canonicalUrl))</guid><pubDate>\(rfc822(post.date))</pubDate><description><![CDATA[\(post.html)]]></description><content:encoded><![CDATA[\(post.html)]]></content:encoded></item>
            """
        }.joined(separator: "\n")
        let feedPath = path.hasPrefix("/") ? path : "/\(path)"
        let siteUrl = cleanBaseUrl(config.site.url)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom"><channel><title>\(escape(feedTitle))</title><link>\(escape(config.site.url))</link><description>\(escape(config.site.description ?? config.site.title))</description><atom:link href="\(escape(siteUrl + feedPath))" rel="self" type="application/rss+xml"/>
        \(items)
        </channel></rss>
        """
    }

    public static func json(config: InksteadWriterConfig, posts: [NormalizedPost]) -> String {
        let items: [[String: Any]] = limitedPosts(config: config, posts: posts).map { post in
            var item: [String: Any] = [
                "id": post.canonicalUrl,
                "url": post.canonicalUrl,
                "content_html": post.html,
                "content_text": plainText(post.html),
                "date_published": iso(post.date),
                "date_modified": iso(post.lastmod ?? post.date)
            ]
            if let title = post.title {
                item["title"] = title
            }
            return item
        }
        var body: [String: Any] = [
            "version": "https://jsonfeed.org/version/1.1",
            "title": config.site.title,
            "home_page_url": "\(cleanBaseUrl(config.site.url))/",
            "feed_url": "\(cleanBaseUrl(config.site.url))/feed.json",
            "authors": [["name": config.site.author, "url": "\(cleanBaseUrl(config.site.url))/"]],
            "items": items
        ]
        if let description = config.site.description {
            body["description"] = description
        }
        let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }

    public static func sitemap(config: InksteadWriterConfig, urls: [String]) -> String {
        let entries = urls.map { "  <url><loc>\(escape($0))</loc></url>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(entries)
        </urlset>
        """
    }

    private static func limitedPosts(config: InksteadWriterConfig, posts: [NormalizedPost]) -> [NormalizedPost] {
        Array(posts.prefix(config.feeds?.limit ?? 25))
    }

    private static func cleanBaseUrl(_ url: String) -> String {
        url.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression)
    }

    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func rfc822(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
