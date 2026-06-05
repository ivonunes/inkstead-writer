import Foundation

public enum FrontmatterValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([FrontmatterValue])
    case object([String: FrontmatterValue])

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var stringArray: [String] {
        guard case .array(let values) = self else { return [] }
        return values.compactMap(\.string)
    }

    public var object: [String: FrontmatterValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public static func from(_ value: Any) -> FrontmatterValue {
        if let value = value as? FrontmatterValue { return value }
        if let value = value as? String { return .string(value) }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Int { return .number(Double(value)) }
        if let value = value as? Double { return .number(value) }
        if let value = value as? [Any] { return .array(value.map(FrontmatterValue.from)) }
        if let value = value as? [String: Any] { return .object(value.mapValues(FrontmatterValue.from)) }
        return .string(String(describing: value))
    }
}

public struct ParsedMarkdown: Equatable, Sendable {
    public var path: URL
    public var slug: String
    public var frontmatter: [String: FrontmatterValue]
    public var body: String
    public var html: String
}

public enum FrontmatterParser {
    public static func parse(_ raw: String) -> (frontmatter: [String: FrontmatterValue], body: String) {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            return ([:], raw)
        }
        let newline = raw.hasPrefix("---\r\n") ? "\r\n" : "\n"
        let marker = "\(newline)---\(newline)"
        guard let close = raw.range(of: marker, range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex) else {
            return ([:], raw)
        }
        let frontmatterStart = raw.index(raw.startIndex, offsetBy: 3 + newline.count)
        let yaml = String(raw[frontmatterStart..<close.lowerBound])
        let body = String(raw[close.upperBound...])
        return (parseYamlSubset(yaml), body)
    }

    public static func parseYamlSubset(_ yaml: String) -> [String: FrontmatterValue] {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        var output: [String: FrontmatterValue] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !rawValue.isEmpty {
                output[key] = scalar(rawValue)
                index += 1
                continue
            }

            var nested: [String] = []
            index += 1
            while index < lines.count, lines[index].hasPrefix("  ") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                nested.append(lines[index])
                index += 1
            }
            output[key] = parseNested(nested)
        }
        return output
    }

    public static func serializeYamlSubset(_ values: [String: FrontmatterValue]) -> String {
        values.keys.sorted().map { key in
            serialize(key: key, value: values[key]!, indent: 0)
        }.joined(separator: "\n")
    }

    private static func serialize(key: String, value: FrontmatterValue, indent: Int) -> String {
        let prefix = String(repeating: " ", count: indent)
        switch value {
        case .string(let string):
            return "\(prefix)\(key): \(quoteIfNeeded(string))"
        case .bool(let bool):
            return "\(prefix)\(key): \(bool ? "true" : "false")"
        case .number(let number):
            return number.rounded() == number ? "\(prefix)\(key): \(Int(number))" : "\(prefix)\(key): \(number)"
        case .array(let values):
            if values.isEmpty { return "\(prefix)\(key): []" }
            let lines = values.map { item -> String in
                switch item {
                case .object(let object):
                    let nested = object.keys.sorted().map { serialize(key: $0, value: object[$0]!, indent: indent + 4) }.joined(separator: "\n")
                    return "\(prefix)  -\n\(nested)"
                default:
                    return "\(prefix)  - \(scalar(item))"
                }
            }
            return "\(prefix)\(key):\n\(lines.joined(separator: "\n"))"
        case .object(let object):
            if object.isEmpty { return "\(prefix)\(key): {}" }
            let lines = object.keys.sorted().map { serialize(key: $0, value: object[$0]!, indent: indent + 2) }
            return "\(prefix)\(key):\n\(lines.joined(separator: "\n"))"
        }
    }

    private static func scalar(_ value: FrontmatterValue) -> String {
        switch value {
        case .string(let string): quoteIfNeeded(string)
        case .bool(let bool): bool ? "true" : "false"
        case .number(let number): number.rounded() == number ? "\(Int(number))" : "\(number)"
        case .array: "[]"
        case .object: "{}"
        }
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        if value.isEmpty { return "\"\"" }
        if value.range(of: #"^[A-Za-z0-9._:/@+-]+$"#, options: .regularExpression) != nil {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func parseNested(_ lines: [String]) -> FrontmatterValue {
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if content.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }) {
            return .array(content.map { line in
                let clean = line.trimmingCharacters(in: .whitespaces)
                return scalar(String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            })
        }

        var object: [String: FrontmatterValue] = [:]
        var index = 0
        while index < content.count {
            let line = content[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(trimmed[..<colon])
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                object[key] = scalar(value)
                index += 1
                continue
            }

            var child: [String] = []
            index += 1
            while index < content.count, content[index].hasPrefix("    ") {
                child.append(String(content[index].dropFirst(2)))
                index += 1
            }
            object[key] = parseNested(child)
        }
        return .object(object)
    }

    private static func scalar(_ raw: String) -> FrontmatterValue {
        let value = unquote(raw)
        if value == "true" { return .bool(true) }
        if value == "false" { return .bool(false) }
        if let number = Double(value), !value.contains(":") {
            return .number(number)
        }
        return .string(value)
    }

    private static func unquote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        if trimmed.first == "\"", trimmed.last == "\"" {
            return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        if trimmed.first == "'", trimmed.last == "'" {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
