import Foundation

public enum MarkdownRenderer {
    public static func render(_ markdown: String, config: InksteadWriterConfig? = nil) -> String {
        let allowHTML = config?.markdown?.html ?? true
        let hardBreaks = config?.markdown?.breaks ?? true
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var html = ""
        for rawBlock in blocks {
            let block = rawBlock.trimmingCharacters(in: .newlines)
            if block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if allowHTML, trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
                html += "\(trimmed)\n"
                continue
            }
            if let heading = heading(trimmed) {
                html += "<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>\n"
                continue
            }
            if let list = list(trimmed) {
                let tag = list.ordered ? "ol" : "ul"
                html += "<\(tag)>\n"
                for item in list.items {
                    html += "<li>\(inline(item))</li>\n"
                }
                html += "</\(tag)>\n"
                continue
            }
            if let quote = blockquote(trimmed, config: config) {
                html += quote
                continue
            }
            if let code = fencedCode(trimmed) {
                html += code
                continue
            }
            let body: String
            if hardBreaks {
                let normalizedBreaks = block.replacingOccurrences(of: #" {2,}\n"#, with: "\n", options: .regularExpression)
                body = inline(normalizedBreaks).replacingOccurrences(of: "\n", with: "<br>\n")
            } else {
                body = inline(block).replacingOccurrences(of: "\n", with: " ")
            }
            html += "<p>\(body)</p>\n"
        }
        return html
    }

    public static func inline(_ markdown: String) -> String {
        var output = escape(markdown)
        var placeholders: [String] = []
        func placeholder(_ value: String) -> String {
            placeholders.append(value)
            let scalar = UnicodeScalar(0xE000 + placeholders.count - 1) ?? UnicodeScalar(0xFFFD)!
            return String(Character(scalar))
        }
        output = replace(pattern: #"`([^`]+)`"#, in: output) { match in
            placeholder("<code>\(match[1])</code>")
        }
        output = replace(pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)"#, in: output) { match in
            let alt = match[1]
            let src = match[2]
            return #"<img src="\#(src)" alt="\#(alt)">"#
        }
        output = replace(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: output) { match in
            #"<a href="\#(match[2])">\#(match[1])</a>"#
        }
        output = replace(pattern: #"\*\*([^*]+)\*\*"#, in: output) { match in
            "<strong>\(match[1])</strong>"
        }
        output = replace(pattern: #"(^|[^*])_([^_]+)_"#, in: output) { match in
            "\(match[1])<em>\(match[2])</em>"
        }
        for (index, value) in placeholders.enumerated() {
            let scalar = UnicodeScalar(0xE000 + index) ?? UnicodeScalar(0xFFFD)!
            output = output.replacingOccurrences(of: String(Character(scalar)), with: value)
        }
        return output.replacingOccurrences(of: "...", with: "…")
    }

    private static func heading(_ block: String) -> (level: Int, text: String)? {
        guard let match = firstMatch(pattern: #"^(#{1,6})\s+(.+)$"#, in: block) else { return nil }
        return (match[1].count, match[2])
    }

    private static func list(_ block: String) -> (ordered: Bool, items: [String])? {
        let lines = block.components(separatedBy: "\n")
        let unordered = lines.compactMap { line -> String? in
            guard let match = firstMatch(pattern: #"^\s*[-*+]\s+(.+)$"#, in: line) else { return nil }
            return match[1]
        }
        if unordered.count == lines.count {
            return (false, unordered)
        }
        let ordered = lines.compactMap { line -> String? in
            guard let match = firstMatch(pattern: #"^\s*\d+[.)]\s+(.+)$"#, in: line) else { return nil }
            return match[1]
        }
        if ordered.count == lines.count {
            return (true, ordered)
        }
        return nil
    }

    private static func blockquote(_ block: String, config: InksteadWriterConfig?) -> String? {
        let lines = block.components(separatedBy: "\n")
        let quoted = lines.compactMap { line -> String? in
            guard let match = firstMatch(pattern: #"^\s*>\s?(.*)$"#, in: line) else { return nil }
            return match[1]
        }
        guard quoted.count == lines.count else { return nil }
        return "<blockquote>\n\(render(quoted.joined(separator: "\n"), config: config))</blockquote>\n"
    }

    private static func fencedCode(_ block: String) -> String? {
        let lines = block.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix("```"), lines.count >= 2, lines.last?.hasPrefix("```") == true else { return nil }
        let body = lines.dropFirst().dropLast().joined(separator: "\n")
        return "<pre><code>\(escapeCode(body))</code></pre>\n"
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

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeCode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

    private static func firstMatch(pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = value as NSString
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            if range.location == NSNotFound { return "" }
            return ns.substring(with: range)
        }
    }
}
