import Foundation

public enum NewPostKind: String {
    case article
    case note
}

public struct CreatePostOptions {
    public var kind: NewPostKind
    public var title: String?
    public var text: String?
    public var date: Date?

    public init(kind: NewPostKind, title: String? = nil, text: String? = nil, date: Date? = nil) {
        self.kind = kind
        self.title = title
        self.text = text
        self.date = date
    }
}

public struct CreatePostResult: Equatable {
    public var path: URL
    public var relativePath: String
    public var content: String
}

public enum PostCreator {
    public static func create(root: URL, config: InksteadWriterConfig, options: CreatePostOptions) throws -> CreatePostResult {
        let date = options.date ?? Date()
        let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = options.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if options.kind == .article && (title?.isEmpty ?? true) {
            throw InksteadWriterError.config("Article posts require a title.")
        }
        if options.kind == .note && (text?.isEmpty ?? true) {
            throw InksteadWriterError.config("Note posts require text.")
        }

        let slug = options.kind == .article
            ? slugForNewPost(title: title, body: "", date: date)
            : slugForNewPost(title: nil, body: text ?? "", date: date)
        let relative = uniquePath(root: root, relativePath: "\(config.content.posts)/\(slug).md")
        // A brand new post has no image yet, so targets that carry a photo
        // rather than a link are left out of the scaffold.
        let syndication = (config.syndication?.providers ?? []).filter { target in
            guard target.provider != .flickr else { return false }
            guard let service = target.service else { return true }
            return !BufferChannels.requiresPhoto(service: service)
        }
        let fields: [(String, String)] = options.kind == .article
            ? [("title", quoteYaml(title ?? "")), ("date", localIso(date))]
            : [("date", localIso(date))]
        let body = options.kind == .note ? "\(text ?? "")\n" : "\n"
        let content = "\(frontmatter(fields: fields, syndication: syndication))\n\n\(body)"
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return CreatePostResult(path: url, relativePath: relative, content: content)
    }

    public static func slugifyTitle(_ title: String) -> String {
        title.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(80)
            .description
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    public static func slugForNewPost(title: String?, body: String = "", date: Date = Date()) -> String {
        let source = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? postSlugText(body, maxLength: 80)
            ?? "untitled-\(timeSuffix(date))"
        let slug = slugifyTitle(source).nilIfEmpty ?? "untitled-\(timeSuffix(date))"
        return "\(datePrefix(date))-\(slug)"
    }

    private static func postSlugText(_ markdown: String, maxLength: Int) -> String? {
        var text = markdown
            .replacingOccurrences(of: #"\r?\n+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*]\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<img\b[^>]*(?:>|$)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\[([^\]]+)]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[`*_>#-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text.removeAll { character in
            character.unicodeScalars.contains { scalar in
                (0x1F300...0x1FAFF).contains(Int(scalar.value)) || scalar.value == 0xFE0F || scalar.value == 0x200D
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.count > maxLength {
            return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func frontmatter(fields: [(String, String)], syndication: [SyndicationTarget]) -> String {
        var lines = fields.map { "\($0.0): \($0.1)" }
        if !syndication.isEmpty {
            lines.append("syndicate:")
            lines.append(contentsOf: syndication.map { "  - \($0.rawValue)" })
        }
        return "---\n\(lines.joined(separator: "\n"))\n---"
    }

    private static func quoteYaml(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(value)\""
    }

    private static func uniquePath(root: URL, relativePath: String) -> String {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path) {
            return relativePath
        }
        let ns = relativePath as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        for index in 2..<1000 {
            let candidate = "\(base)-\(index).\(ext)"
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path) {
                return candidate
            }
        }
        return relativePath
    }

    private static func datePrefix(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func timeSuffix(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func localIso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
