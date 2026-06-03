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

func serializePost(_ post: NormalizedPost) -> [String: Any] {
    [
        "slug": post.slug,
        "kind": post.kind.rawValue,
        "title": post.title ?? "",
        "displayTitle": post.title ?? (post.kind == .photoNote ? "Photo note" : "Note"),
        "html": PlumeSafeHTML(post.html),
        "excerpt": PlumeSafeHTML(post.excerpt),
        "hasMore": post.hasMore,
        "dateIso": ISO8601DateFormatter().string(from: post.date),
        "dateDisplay": ContentLoader.dateDisplay(post.date),
        "dateLongDisplay": ContentLoader.dateLongDisplay(post.date),
        "date_long_display": ContentLoader.dateLongDisplay(post.date),
        "lastmodIso": post.lastmod.map { ISO8601DateFormatter().string(from: $0) } ?? "",
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

func serializeCategory(_ category: CategoryCollection) -> [String: Any] {
    [
        "name": category.name,
        "slug": category.slug,
        "urlPath": category.urlPath,
        "feedPath": category.feedPath,
        "jsonFeedPath": category.feedPath.replacingOccurrences(of: "feed.xml", with: "feed.json"),
        "posts": category.posts.map(serializePost)
    ]
}

func serializeCustomCollectionItem(_ item: CustomCollectionItem) -> [String: Any] {
    var output = ContentLoader.frontmatterDictionary(item.frontmatter)
    output["collection"] = item.collection
    output["slug"] = item.slug
    output["path"] = item.relativePath
    output["body"] = item.body
    output["html"] = PlumeSafeHTML(item.html)
    output["content"] = PlumeSafeHTML(item.html)
    if let date = item.frontmatter["date"]?.string.flatMap(ContentLoader.parseDate) {
        output["dateIso"] = ISO8601DateFormatter().string(from: date)
        output["dateDisplay"] = ContentLoader.dateDisplay(date)
        output["dateLongDisplay"] = ContentLoader.dateLongDisplay(date)
        output["date_long_display"] = ContentLoader.dateLongDisplay(date)
    }
    return output
}
