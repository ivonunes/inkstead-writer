import Foundation

public enum PostKind: String, Equatable, Sendable {
    case article
    case note
    case photoNote = "photo-note"
}

public struct NormalizedPost: Equatable, @unchecked Sendable {
    public var parsed: ParsedMarkdown
    public var kind: PostKind
    public var title: String?
    public var summary: String?
    public var excerpt: String
    public var hasMore: Bool
    public var date: Date
    public var lastmod: Date?
    public var urlPath: String
    public var canonicalUrl: String
    public var photos: [String]
    public var sourcePhotos: [String]
    public var firstImage: String?
    public var alt: String?
    public var categories: [String]
    public var syndicate: [SyndicationProviderName]
    public var syndication: [String: FrontmatterValue]
    public var syndicationUrls: [String]
    public var previous: String?
    public var next: String?

    public var html: String { parsed.html }
    public var slug: String { parsed.slug }
    public var path: URL { parsed.path }
}

public struct NormalizedPage: Equatable, @unchecked Sendable {
    public var parsed: ParsedMarkdown
    public var title: String
    public var summary: String?
    public var excerpt: String
    public var urlPath: String
    public var canonicalUrl: String

    public var html: String { parsed.html }
    public var slug: String { parsed.slug }
}

public struct CategoryCollection: Equatable, @unchecked Sendable {
    public var name: String
    public var slug: String
    public var urlPath: String
    public var feedPath: String
    public var posts: [NormalizedPost]
}

public struct CustomCollectionItem: Equatable, @unchecked Sendable {
    public var parsed: ParsedMarkdown
    public var collection: String
    public var slug: String
    public var relativePath: String

    public var html: String { parsed.html }
    public var body: String { parsed.body }
    public var frontmatter: [String: FrontmatterValue] { parsed.frontmatter }
}

public enum ContentLoader {
    public static func parseMarkdownFile(_ file: URL, config: InksteadWriterConfig) throws -> ParsedMarkdown {
        let raw = try String(contentsOf: file, encoding: .utf8)
        let parsed = FrontmatterParser.parse(raw)
        return ParsedMarkdown(
            path: file,
            slug: slugFromFile(file),
            frontmatter: parsed.frontmatter,
            body: parsed.body,
            html: MarkdownRenderer.render(parsed.body, config: config)
        )
    }

    public static func loadPosts(root: URL, config: InksteadWriterConfig) throws -> [NormalizedPost] {
        let postsRoot = root.appendingPathComponent(config.content.posts)
        let files = try markdownFiles(in: postsRoot)
        var posts = try BuildConcurrency.map(files) {
                try normalizePost(parseMarkdownFile($0, config: config), config: config, root: root)
            }
            .filter { $0.parsed.frontmatter["status"]?.string?.lowercased() != "draft" }
            .sorted { $0.date > $1.date }
        for index in posts.indices {
            posts[index].next = index > 0 ? posts[index - 1].urlPath : nil
            posts[index].previous = index < posts.count - 1 ? posts[index + 1].urlPath : nil
        }
        return posts
    }

    public static func loadPages(root: URL, config: InksteadWriterConfig) throws -> [NormalizedPage] {
        let pagesRoot = root.appendingPathComponent(config.content.pages)
        return try BuildConcurrency.map(markdownFiles(in: pagesRoot)) {
            try normalizePage(parseMarkdownFile($0, config: config), config: config)
        }
    }

    public static func loadCollections(root: URL, config: InksteadWriterConfig) throws -> [String: [CustomCollectionItem]] {
        let collectionsRoot = root.appendingPathComponent(config.content.collections)
        guard FileManager.default.fileExists(atPath: collectionsRoot.path) else {
            return [:]
        }
        let reserved = Set(["posts", "pages", "categories", "photoPosts"])
        let directories = try FileManager.default.contentsOfDirectory(at: collectionsRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var collections: [String: [CustomCollectionItem]] = [:]
        for directory in directories {
            let name = directory.lastPathComponent
            guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw InksteadWriterError.config("Collection directory \(name) must be a valid Plume identifier.")
            }
            guard !reserved.contains(name) else {
                throw InksteadWriterError.config("Collection directory \(name) conflicts with a built-in collection.")
            }
            let items = try BuildConcurrency.map(markdownFiles(in: directory)) {
                    try normalizeCollectionItem(parseMarkdownFile($0, config: config), collection: name, root: root)
                }
                .filter { $0.frontmatter["status"]?.string?.lowercased() != "draft" }
            collections[name] = sortCollectionItems(items)
        }
        return collections
    }

    public static func normalizePost(_ parsed: ParsedMarkdown, config: InksteadWriterConfig, root: URL) throws -> NormalizedPost {
        guard let dateValue = parsed.frontmatter["date"] else {
            throw InksteadWriterError.config("\(parsed.path.path) is missing required date frontmatter.")
        }
        let dateText = dateValue.string ?? String(describing: frontmatterValue(dateValue))
        guard let date = parseDate(dateText) else {
            throw InksteadWriterError.config("\(parsed.path.path) could not parse date '\(dateText)' (expected ISO 8601, e.g. 2026-06-09T12:00:00Z or 2026-06-09).")
        }
        let lastmod = parsed.frontmatter["lastmod"]?.string.flatMap(parseDate)
        let title = parsed.frontmatter["title"]?.string
        let frontmatterPhotos = parsed.frontmatter["photos"]?.stringArray ?? []
        let bodyImages = images(in: parsed.body)
        let kind = inferKind(title: title, photos: frontmatterPhotos, bodyImages: bodyImages)
        let urlPath = postUrlPath(parsed: parsed, config: config, date: date, timeZone: try siteTimeZone(config))
        let excerpt = excerptData(parsed: parsed, config: config)
        let categories = uniqueCategories(directoryCategories(file: parsed.path, root: root, config: config) + frontmatterCategories(parsed.frontmatter))
        let syndication = parsed.frontmatter["syndication"]?.object ?? [:]
        let html = kind == .photoNote ? addImageClass(parsed.html, className: "u-photo") : parsed.html
        let updatedParsed = ParsedMarkdown(path: parsed.path, slug: parsed.slug, frontmatter: parsed.frontmatter, body: parsed.body, html: html)

        return NormalizedPost(
            parsed: updatedParsed,
            kind: kind,
            title: title,
            summary: excerpt.summary,
            excerpt: excerpt.html,
            hasMore: excerpt.hasMore,
            date: date,
            lastmod: lastmod,
            urlPath: urlPath,
            canonicalUrl: "\(cleanBaseUrl(config.site.url))\(urlPath)",
            photos: frontmatterPhotos,
            sourcePhotos: sourcePhotoPaths(refs: frontmatterPhotos + bodyImages, parsed: parsed, config: config, root: root),
            firstImage: bodyImages.first ?? frontmatterPhotos.first,
            alt: parsed.frontmatter["alt"]?.string,
            categories: categories,
            syndicate: (parsed.frontmatter["syndicate"]?.stringArray ?? []).compactMap(SyndicationProviderName.init(rawValue:)),
            syndication: syndication,
            syndicationUrls: syndicationUrls(parsed.frontmatter["syndication"]),
            previous: nil,
            next: nil
        )
    }

    public static func normalizePage(_ parsed: ParsedMarkdown, config: InksteadWriterConfig) -> NormalizedPage {
        let title = parsed.frontmatter["title"]?.string ?? parsed.slug
        let excerpt = excerptData(parsed: parsed, config: config)
        let urlPath = "/\(parsed.slug)/"
        return NormalizedPage(
            parsed: parsed,
            title: title,
            summary: excerpt.summary,
            excerpt: excerpt.html,
            urlPath: urlPath,
            canonicalUrl: "\(cleanBaseUrl(config.site.url))\(urlPath)"
        )
    }

    public static func normalizeCollectionItem(_ parsed: ParsedMarkdown, collection: String, root: URL) -> CustomCollectionItem {
        CustomCollectionItem(
            parsed: parsed,
            collection: collection,
            slug: parsed.frontmatter["slug"]?.string ?? parsed.slug,
            relativePath: relativePath(parsed.path, root: root)
        )
    }

    public static func groupPostsByCategory(_ posts: [NormalizedPost]) -> [CategoryCollection] {
        var map: [String: CategoryCollection] = [:]
        for post in posts {
            for category in post.categories {
                let slug = slugifyCategory(category)
                if slug.isEmpty { continue }
                if map[slug] != nil {
                    map[slug]?.posts.append(post)
                } else {
                    map[slug] = CategoryCollection(name: category, slug: slug, urlPath: "/categories/\(slug)/", feedPath: "/categories/\(slug)/feed.xml", posts: [post])
                }
            }
        }
        return map.values.sorted { $0.name < $1.name }
    }

    public static func isGalleryPhotoPost(_ post: NormalizedPost) -> Bool {
        guard post.kind == .photoNote else { return false }
        let image = post.firstImage ?? post.photos.first ?? ""
        return URL(fileURLWithPath: image.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? image).pathExtension.lowercased() != "png"
    }

    public static func slugifyCategory(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static let dateFormatters = DateFormatters()

    public static let utcTimeZone = TimeZone(identifier: "UTC")!

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func siteTimeZone(_ config: InksteadWriterConfig) throws -> TimeZone {
        guard let identifier = config.site.timezone, !identifier.isEmpty else { return utcTimeZone }
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw InksteadWriterError.config("site.timezone '\(identifier)' is not a valid timezone identifier (e.g. Europe/Lisbon).")
        }
        return timeZone
    }

    private final class DateFormatters: @unchecked Sendable {
        let isoFractional: ISO8601DateFormatter
        let iso: ISO8601DateFormatter
        private let lock = NSLock()
        private let utcDateTime: DateFormatter
        private let utcDateOnly: DateFormatter
        private let display: DateFormatter

        init() {
            isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            utcDateTime = Self.utcFormatter("yyyy-MM-dd'T'HH:mm:ss")
            utcDateOnly = Self.utcFormatter("yyyy-MM-dd")
            display = Self.utcFormatter("MMMM d, yyyy")
        }

        private static func utcFormatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }

        func fallbackDate(from value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return utcDateTime.date(from: value) ?? utcDateOnly.date(from: value)
        }

        func displayString(from date: Date, timeZone: TimeZone) -> String {
            lock.lock()
            defer { lock.unlock() }
            if display.timeZone != timeZone {
                display.timeZone = timeZone
            }
            return display.string(from: date)
        }
    }

    public static func parseDate(_ value: String) -> Date? {
        if let date = dateFormatters.isoFractional.date(from: value) { return date }
        if let date = dateFormatters.iso.date(from: value) { return date }
        return dateFormatters.fallbackDate(from: value)
    }

    public static func dateDisplay(_ date: Date, timeZone: TimeZone = ContentLoader.utcTimeZone) -> String {
        dateFormatters.displayString(from: date, timeZone: timeZone)
    }

    public static func dateLongDisplay(_ date: Date, timeZone: TimeZone = ContentLoader.utcTimeZone) -> String {
        dateDisplay(date, timeZone: timeZone)
    }

    public static func frontmatterDictionary(_ values: [String: FrontmatterValue]) -> [String: Any] {
        values.mapValues(frontmatterValue)
    }

    public static func frontmatterValue(_ value: FrontmatterValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .bool(let bool):
            return bool
        case .number(let number):
            return number.rounded() == number ? Int(number) : number
        case .array(let values):
            return values.map(frontmatterValue)
        case .object(let object):
            return object.mapValues(frontmatterValue)
        }
    }

    public static func slugFromFile(_ file: URL) -> String {
        file.deletingPathExtension().lastPathComponent
    }

    private static func markdownFiles(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true && url.pathExtension.lowercased() == "md" ? url : nil
        }.sorted { $0.path < $1.path }
    }

    private struct CollectionSortKey {
        var order: Double?
        var date: Date?
        var title: String?
        var relativePath: String

        init(_ item: CustomCollectionItem) {
            order = item.frontmatter["order"]?.number
            date = item.frontmatter["date"]?.string.flatMap(parseDate)
            title = item.frontmatter["title"]?.string
            relativePath = item.relativePath
        }
    }

    private static func sortCollectionItems(_ items: [CustomCollectionItem]) -> [CustomCollectionItem] {
        items.map { (item: $0, key: CollectionSortKey($0)) }
            .sorted { compareCollectionItems($0.key, $1.key) }
            .map(\.item)
    }

    private static func compareCollectionItems(_ left: CollectionSortKey, _ right: CollectionSortKey) -> Bool {
        if let leftOrder = left.order, let rightOrder = right.order {
            if leftOrder != rightOrder { return leftOrder < rightOrder }
        } else if left.order != nil {
            return true
        } else if right.order != nil {
            return false
        }

        if let leftDate = left.date, let rightDate = right.date {
            if leftDate != rightDate { return leftDate > rightDate }
        } else if left.date != nil {
            return true
        } else if right.date != nil {
            return false
        }

        if let leftTitle = left.title, let rightTitle = right.title, leftTitle != rightTitle {
            return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
        }
        return left.relativePath < right.relativePath
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        FileTreeSupport.relativePath(of: url, under: root)
            ?? url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func inferKind(title: String?, photos: [String], bodyImages: [String]) -> PostKind {
        if let title, !title.isEmpty { return .article }
        if !photos.isEmpty || !bodyImages.isEmpty { return .photoNote }
        return .note
    }

    private static func postUrlPath(parsed: ParsedMarkdown, config: InksteadWriterConfig, date: Date, timeZone: TimeZone) -> String {
        if let url = parsed.frontmatter["url"]?.string { return url }
        let slug = parsed.slug.replacingOccurrences(of: #"^\d{4}-\d{2}-\d{2}-"#, with: "", options: .regularExpression)
        if config.urls?.posts == .slug { return "/posts/\(slug)/" }
        var calendar = utcCalendar
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "/%04d/%02d/%02d/%@/", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, slug)
    }

    private static func cleanBaseUrl(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    private static func images(in body: String) -> [String] {
        var output: [String] = []
        for pattern in [#"!\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)"#, #"<img[^>]+src=["']([^"']+)["']"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = body as NSString
            for match in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: match.range(at: 1))
                if !output.contains(value) { output.append(value) }
            }
        }
        return output
    }

    private static func sourcePhotoPaths(refs: [String], parsed: ParsedMarkdown, config: InksteadWriterConfig, root: URL) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for ref in refs {
            if ref.range(of: #"^https?://"#, options: .regularExpression) != nil { continue }
            let path: String
            if ref.hasPrefix("/media/") {
                path = root.appendingPathComponent(config.content.media).appendingPathComponent(String(ref.dropFirst("/media/".count))).path
            } else if ref.hasPrefix("/") {
                path = root.appendingPathComponent(String(ref.dropFirst())).path
            } else if ref.hasPrefix("\(config.content.media)/") {
                path = root.appendingPathComponent(ref).path
            } else {
                let mediaPath = root.appendingPathComponent(config.content.media).appendingPathComponent(ref).path
                path = FileManager.default.fileExists(atPath: mediaPath) ? mediaPath : parsed.path.deletingLastPathComponent().appendingPathComponent(ref).path
            }
            if !seen.contains(path) {
                seen.insert(path)
                output.append(path)
            }
        }
        return output
    }

    private static func addImageClass(_ html: String, className: String) -> String {
        html.replacingOccurrences(of: #"<img\b([^>]*)>"#, with: #"<img class="\#(className)"$1>"#, options: [.regularExpression, .caseInsensitive])
    }

    private static func frontmatterCategories(_ frontmatter: [String: FrontmatterValue]) -> [String] {
        if let category = frontmatter["category"]?.string { return [category].filter { !$0.isEmpty } }
        return frontmatter["categories"]?.stringArray.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
    }

    private static func directoryCategories(file: URL, root: URL, config: InksteadWriterConfig) -> [String] {
        let postsRoot = root.appendingPathComponent(config.content.posts)
        let directory = file.deletingLastPathComponent()
        guard let relative = FileTreeSupport.relativePath(of: directory, under: postsRoot), !relative.isEmpty else { return [] }
        return relative.split(separator: "/").map { segment in
            segment.replacingOccurrences(of: #"[-_]+"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private static func uniqueCategories(_ categories: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for category in categories {
            let key = slugifyCategory(category)
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            output.append(category)
        }
        return output
    }

    private static func syndicationUrls(_ value: FrontmatterValue?) -> [String] {
        guard let value else { return [] }
        if case .array(let values) = value {
            return values.compactMap(\.string)
        }
        if case .object(let providers) = value {
            return providers.values.compactMap { provider in
                provider.object?["url"]?.string
            }
        }
        return []
    }

    private static func excerptData(parsed: ParsedMarkdown, config: InksteadWriterConfig, wordLimit: Int = 70) -> (summary: String?, html: String, hasMore: Bool) {
        if let summary = parsed.frontmatter["summary"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return (summary, MarkdownRenderer.render(summary, config: config), true)
        }
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let moreParts = body.components(separatedBy: "<!--more-->")
        if moreParts.count > 1 {
            let intro = moreParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, MarkdownRenderer.render(intro, config: config), true)
        }
        guard let blocks = topLevelHTMLBlocks(parsed.html) else {
            // Raw HTML in the post broke block detection; a plain-text excerpt
            // beats emitting unbalanced markup into every index page.
            let stripped = plainExcerptText(from: parsed.html)
            let words = stripped.split(separator: " ")
            if words.count <= wordLimit {
                return (nil, stripped, false)
            }
            return (nil, "<p>" + words.prefix(wordLimit).joined(separator: " ") + "…</p>", true)
        }

        var kept: [String] = []
        var wordCount = 0
        var index = 0
        var truncatedMidBlock = false
        while index < blocks.count {
            let block = stripMedia(from: blocks[index])
            index += 1
            let text = plainExcerptText(from: block)
            if text.isEmpty { continue }
            let words = text.split(separator: " ").count
            if kept.isEmpty && words > wordLimit * 3 / 2 {
                // A single opening block far over the limit: fall back to a
                // word-truncated paragraph rather than a huge excerpt.
                let truncated = text.split(separator: " ").prefix(wordLimit).joined(separator: " ")
                kept.append("<p>\(truncated)…</p>")
                wordCount += words
                truncatedMidBlock = true
                break
            }
            kept.append(block)
            wordCount += words
            if wordCount >= wordLimit { break }
        }
        let remainingText = blocks[min(index, blocks.count)...]
            .map { plainExcerptText(from: stripMedia(from: $0)) }
            .contains { !$0.isEmpty }
        let hasMore = truncatedMidBlock || remainingText
        var html = kept.joined(separator: "\n")
        if hasMore && !truncatedMidBlock {
            if html.hasSuffix("</p>") {
                html = String(html.dropLast(4)) + "…</p>"
            } else {
                html += "\n<p>…</p>"
            }
        }
        return (nil, html, hasMore)
    }

    private static func stripMedia(from html: String) -> String {
        html
            .replacingOccurrences(of: #"<(figure|video|audio)\b[^>]*>[\s\S]*?</\1\s*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<img\b[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    private static func plainExcerptText(from html: String) -> String {
        stripMedia(from: html)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let voidHTMLTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    /// Splits rendered HTML into complete top-level elements, or nil when the
    /// markup is unbalanced (possible with raw HTML passthrough in posts).
    /// The Markdown renderer escapes `<` in text and code, so every literal
    /// `<` in its output starts a real tag.
    static func topLevelHTMLBlocks(_ html: String) -> [String]? {
        var blocks: [String] = []
        var current = ""
        var depth = 0
        var index = html.startIndex

        func flush() {
            let block = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty { blocks.append(block) }
            current = ""
        }

        while index < html.endIndex {
            guard html[index] == "<", let close = html[index...].firstIndex(of: ">") else {
                current.append(html[index])
                index = html.index(after: index)
                continue
            }
            let tag = String(html[index...close])
            index = html.index(after: close)
            current += tag
            if tag.hasPrefix("<!") {
                if depth == 0 { flush() }
                continue
            }
            let isClosing = tag.hasPrefix("</")
            let nameStart = tag.index(tag.startIndex, offsetBy: isClosing ? 2 : 1)
            let name = tag[nameStart...].prefix { $0.isLetter || $0.isNumber }.lowercased()
            if name.isEmpty { return nil }
            if isClosing {
                depth -= 1
                if depth < 0 { return nil }
                if depth == 0 { flush() }
            } else if !voidHTMLTags.contains(name) && !tag.hasSuffix("/>") {
                depth += 1
            } else if depth == 0 {
                flush()
            }
        }
        guard depth == 0 else { return nil }
        let leftover = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leftover.isEmpty else { return nil }
        return blocks
    }
}
