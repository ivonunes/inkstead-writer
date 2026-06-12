import Foundation
import Plume

func firstPlumeArgument(_ call: PlumeFunctionCall) -> Any? {
    guard !call.arguments.isEmpty else { return nil }
    return call.arguments[0]
}

func plumeArgument(named name: String, in call: PlumeFunctionCall) -> Any? {
    guard let value = call.namedArguments[name] else { return nil }
    return value
}

func stringifyPlumeValue(_ value: Any?) -> String {
    guard let value else { return "" }
    if value is NSNull { return "" }
    if let safe = value as? PlumeSafeHTML { return safe.html }
    if let string = value as? String { return string }
    if let bool = value as? Bool { return bool ? "true" : "false" }
    if let int = value as? Int { return String(int) }
    if let double = value as? Double { return String(double) }
    if let array = value as? [Any] { return array.map(stringifyPlumeValue).filter { !$0.isEmpty }.joined(separator: " ") }
    return String(describing: value)
}

func escapeAttribute(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func serializeSite(_ site: SiteConfig) -> [String: Any] {
    [
        "title": site.title,
        "url": site.url,
        "author": site.author,
        "description": site.description ?? "",
        "lang": site.lang ?? "",
        "timezone": site.timezone ?? "",
        "email": site.email ?? "",
        "avatar": site.avatar ?? "",
        "bio": site.bio ?? "",
        "navigation": site.navigation?.map {
            [
                "name": $0.name,
                "url": $0.url,
                "icon": $0.icon ?? "",
                "className": $0.className ?? ""
            ]
        } ?? [],
        "social": site.social?.map {
            [
                "name": $0.name,
                "url": $0.url,
                "relMe": $0.relMe ?? false,
                "icon": $0.icon ?? "",
                "className": $0.className ?? ""
            ]
        } ?? []
    ]
}

func serializeConfig(_ config: InksteadWriterConfig) -> [String: Any] {
    [
        "theme": [
            "showPoweredBy": config.theme?.showPoweredBy as Any
        ]
    ]
}

enum ThemeDateFormatting {
    /// ISO8601DateFormatter is documented as thread-safe, so a shared instance is safe.
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()

    static func iso8601String(from date: Date) -> String {
        iso8601.string(from: date)
    }
}

func serializePost(_ post: NormalizedPost, timeZone: TimeZone) -> [String: Any] {
    [
        "slug": post.slug,
        "kind": post.kind.rawValue,
        "title": post.title ?? "",
        "displayTitle": post.title ?? (post.kind == .photoNote ? "Photo note" : "Note"),
        "html": PlumeSafeHTML(post.html),
        "excerpt": PlumeSafeHTML(post.excerpt),
        "hasMore": post.hasMore,
        "dateIso": ThemeDateFormatting.iso8601String(from: post.date),
        "dateDisplay": ContentLoader.dateDisplay(post.date, timeZone: timeZone),
        "dateLongDisplay": ContentLoader.dateLongDisplay(post.date, timeZone: timeZone),
        "date_long_display": ContentLoader.dateLongDisplay(post.date, timeZone: timeZone),
        "lastmodIso": post.lastmod.map { ThemeDateFormatting.iso8601String(from: $0) } ?? "",
        "urlPath": post.urlPath,
        "canonicalUrl": post.canonicalUrl,
        "photos": post.photos,
        "firstImage": post.firstImage ?? "",
        "alt": post.alt ?? "",
        "categories": post.categories,
        "categoryLinks": post.categories.map { ["name": $0, "slug": ContentLoader.slugifyCategory($0), "url": "/categories/\(ContentLoader.slugifyCategory($0))/"] },
        "syndicationUrls": post.syndicationUrls
    ]
}

func serializePage(_ page: NormalizedPage) -> [String: Any] {
    [
        "slug": page.slug,
        "title": page.title,
        "html": PlumeSafeHTML(page.html),
        "excerpt": PlumeSafeHTML(page.excerpt),
        "urlPath": page.urlPath,
        "canonicalUrl": page.canonicalUrl
    ]
}

func serializeCategory(_ category: CategoryCollection, timeZone: TimeZone) -> [String: Any] {
    serializeCategory(category, postsByURL: [:], timeZone: timeZone)
}

func serializeCategory(_ category: CategoryCollection, postsByURL: [String: [String: Any]], timeZone: TimeZone) -> [String: Any] {
    [
        "name": category.name,
        "slug": category.slug,
        "urlPath": category.urlPath,
        "feedPath": category.feedPath,
        "jsonFeedPath": category.feedPath.replacingOccurrences(of: "feed.xml", with: "feed.json"),
        "posts": category.posts.map { postsByURL[$0.canonicalUrl] ?? serializePost($0, timeZone: timeZone) }
    ]
}

func serializeCustomCollectionItem(_ item: CustomCollectionItem, timeZone: TimeZone) -> [String: Any] {
    var output = ContentLoader.frontmatterDictionary(item.frontmatter)
    output["collection"] = item.collection
    output["slug"] = item.slug
    output["path"] = item.relativePath
    output["body"] = item.body
    output["html"] = PlumeSafeHTML(item.html)
    output["content"] = PlumeSafeHTML(item.html)
    if let date = item.frontmatter["date"]?.string.flatMap(ContentLoader.parseDate) {
        output["dateIso"] = ThemeDateFormatting.iso8601String(from: date)
        output["dateDisplay"] = ContentLoader.dateDisplay(date, timeZone: timeZone)
        output["dateLongDisplay"] = ContentLoader.dateLongDisplay(date, timeZone: timeZone)
        output["date_long_display"] = ContentLoader.dateLongDisplay(date, timeZone: timeZone)
    }
    return output
}
