import Foundation
import cmark_gfm
import cmark_gfm_extensions

public enum MarkdownRenderer {
    public static func render(_ markdown: String, config: InksteadWriterConfig? = nil) -> String {
        let allowHTML = config?.markdown?.html ?? true
        let hardBreaks = config?.markdown?.breaks ?? true
        var options = CMARK_OPT_SMART | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8
        if allowHTML {
            options |= CMARK_OPT_UNSAFE
        }
        if hardBreaks {
            options |= CMARK_OPT_HARDBREAKS
        }
        return normalizeVoidElements(renderGFM(markdown, options: options))
    }

    public static func inline(_ markdown: String) -> String {
        let html = render(markdown).trimmingCharacters(in: .whitespacesAndNewlines)
        guard html.hasPrefix("<p>"), html.hasSuffix("</p>") else { return html }
        let body = String(html.dropFirst("<p>".count).dropLast("</p>".count))
        guard !body.contains("<p>") else { return html }
        return body
    }

    private static let coreExtensionsRegistered: Bool = {
        cmark_gfm_core_extensions_ensure_registered()
        return true
    }()

    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]

    private static func renderGFM(_ markdown: String, options: Int32) -> String {
        _ = coreExtensionsRegistered
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        cmark_parser_feed(parser, normalized, normalized.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let rendered = cmark_render_html(document, options, nil) else { return "" }
        defer { free(rendered) }
        return String(cString: rendered)
    }

    private static func normalizeVoidElements(_ html: String) -> String {
        html.replacingOccurrences(of: #"<(br|hr|img|input)(\b[^>]*?)\s*/>"#, with: "<$1$2>", options: .regularExpression)
    }

    public static func plainTextForSyndication(_ markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let withoutImages = replace(pattern: #"!\[[^\]]*\]\([^)]*\)"#, in: normalized) { _ in "" }
        var text = replace(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: withoutImages) { match in
            "\(match[1]) (\(match[2]))"
        }
        text = replace(pattern: #"`([^`]+)`"#, in: text) { $0[1] }
        text = replace(pattern: #"\*\*([^*]+)\*\*"#, in: text) { $0[1] }
        text = replace(pattern: #"_([^_]+)_"#, in: text) { $0[1] }
        text = replace(pattern: #"<[^>]+>"#, in: text) { _ in "" }
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(pattern: String, in value: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let ns = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed()
        var output = value
        for match in matches {
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                if range.location == NSNotFound { return "" }
                return ns.substring(with: range)
            }
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: transform(groups))
            }
        }
        return output
    }
}
