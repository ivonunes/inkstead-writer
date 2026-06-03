import Foundation

public enum ConfigLoader {
    public static func load(root: URL) throws -> InksteadWriterConfig {
        let jsonURL = root.appendingPathComponent(InksteadWriterMetadata.configFileName)
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            let data = try Data(contentsOf: jsonURL)
            return try validateVersion(JSONDecoder().decode(InksteadWriterConfig.self, from: data))
        }

        let legacyJSONURL = root.appendingPathComponent(InksteadWriterMetadata.legacyConfigFileName)
        if FileManager.default.fileExists(atPath: legacyJSONURL.path) {
            let data = try Data(contentsOf: legacyJSONURL)
            return try validateVersion(JSONDecoder().decode(InksteadWriterConfig.self, from: data))
        }

        let tsURL = root.appendingPathComponent("site.config.ts")
        guard FileManager.default.fileExists(atPath: tsURL.path) else {
            throw InksteadWriterError.config("\(InksteadWriterMetadata.configFileName), \(InksteadWriterMetadata.legacyConfigFileName), or site.config.ts was not found.")
        }
        let source = try String(contentsOf: tsURL, encoding: .utf8)
        return try validateVersion(loadTypeScriptConfig(source))
    }

    public static func loadTypeScriptConfig(_ source: String) throws -> InksteadWriterConfig {
        let literal = try extractDefineConfigLiteral(source)
        let parsed = try TypeScriptLiteralParser(literal).parse()
        let data = try JSONSerialization.data(withJSONObject: parsed, options: [])
        return try validateVersion(JSONDecoder().decode(InksteadWriterConfig.self, from: data))
    }

    private static func validateVersion(_ config: InksteadWriterConfig) throws -> InksteadWriterConfig {
        let version = config.recordedVersion
        guard InksteadWriterVersion(version) <= InksteadWriterVersion(InksteadWriterMetadata.currentVersion) else {
            throw InksteadWriterError.config("This site was created with Inkstead Writer \(version). Install a newer Inkstead Writer binary before building or migrating it.")
        }
        return config
    }

    private static func extractDefineConfigLiteral(_ source: String) throws -> String {
        guard let callRange = source.range(of: "defineConfig") else {
            throw InksteadWriterError.config("defineConfig(...) was not found.")
        }
        guard let openIndex = source[callRange.upperBound...].firstIndex(of: "(") else {
            throw InksteadWriterError.config("defineConfig(...) is missing its opening parenthesis.")
        }

        var depth = 0
        var inString: Character?
        var escape = false
        var closeIndex: String.Index?
        var index = openIndex
        while index < source.endIndex {
            let char = source[index]
            if let quote = inString {
                if escape {
                    escape = false
                } else if char == "\\" {
                    escape = true
                } else if char == quote {
                    inString = nil
                }
            } else if char == "\"" || char == "'" {
                inString = char
            } else if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    closeIndex = index
                    break
                }
            }
            index = source.index(after: index)
        }
        guard let closeIndex else {
            throw InksteadWriterError.config("defineConfig(...) is missing its closing parenthesis.")
        }
        return String(source[source.index(after: openIndex)..<closeIndex])
    }
}

private final class TypeScriptLiteralParser {
    private let input: [Character]
    private var index = 0

    init(_ source: String) {
        input = Array(source)
    }

    func parse() throws -> Any {
        skipTrivia()
        let value = try parseValue()
        skipTrivia()
        return value
    }

    private func parseValue() throws -> Any {
        skipTrivia()
        guard let char = peek() else {
            throw InksteadWriterError.parse("Unexpected end of config literal.")
        }
        if char == "{" { return try parseObject() }
        if char == "[" { return try parseArray() }
        if char == "\"" || char == "'" { return try parseString() }
        if char == "-" || char.isNumber { return try parseNumber() }
        let identifier = try parseIdentifier()
        switch identifier {
        case "true": return true
        case "false": return false
        case "null", "undefined": return NSNull()
        default:
            return identifier
        }
    }

    private func parseObject() throws -> [String: Any] {
        try consume("{")
        var object: [String: Any] = [:]
        while true {
            skipTrivia()
            if try consumeIf("}") { return object }
            let key = try parseKey()
            skipTrivia()
            try consume(":")
            object[key] = try parseValue()
            skipTrivia()
            if try consumeIf(",") { continue }
            try consume("}")
            return object
        }
    }

    private func parseArray() throws -> [Any] {
        try consume("[")
        var array: [Any] = []
        while true {
            skipTrivia()
            if try consumeIf("]") { return array }
            array.append(try parseValue())
            skipTrivia()
            if try consumeIf(",") { continue }
            try consume("]")
            return array
        }
    }

    private func parseKey() throws -> String {
        skipTrivia()
        guard let char = peek() else {
            throw InksteadWriterError.parse("Unexpected end while reading object key.")
        }
        if char == "\"" || char == "'" { return try parseString() }
        return try parseIdentifier()
    }

    private func parseString() throws -> String {
        guard let quote = peek(), quote == "\"" || quote == "'" else {
            throw InksteadWriterError.parse("Expected string literal.")
        }
        index += 1
        var output = ""
        var escape = false
        while let char = peek() {
            index += 1
            if escape {
                switch char {
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                default: output.append(char)
                }
                escape = false
            } else if char == "\\" {
                escape = true
            } else if char == quote {
                return output
            } else {
                output.append(char)
            }
        }
        throw InksteadWriterError.parse("Unterminated string literal.")
    }

    private func parseNumber() throws -> Any {
        let start = index
        if peek() == "-" { index += 1 }
        while peek()?.isNumber == true { index += 1 }
        if peek() == "." {
            index += 1
            while peek()?.isNumber == true { index += 1 }
        }
        let raw = String(input[start..<index])
        if let int = Int(raw) { return int }
        if let double = Double(raw) { return double }
        throw InksteadWriterError.parse("Invalid number literal \(raw).")
    }

    private func parseIdentifier() throws -> String {
        skipTrivia()
        let start = index
        while let char = peek(), char.isLetter || char.isNumber || char == "_" || char == "-" {
            index += 1
        }
        if start == index {
            throw InksteadWriterError.parse("Expected identifier.")
        }
        return String(input[start..<index])
    }

    private func skipTrivia() {
        while let char = peek(), char.isWhitespace {
            index += 1
        }
        if peek() == "/", peek(ahead: 1) == "/" {
            while let char = peek(), char != "\n" { index += 1 }
            skipTrivia()
        }
    }

    private func consume(_ expected: Character) throws {
        skipTrivia()
        guard peek() == expected else {
            throw InksteadWriterError.parse("Expected \(expected).")
        }
        index += 1
    }

    private func consumeIf(_ expected: Character) throws -> Bool {
        skipTrivia()
        if peek() == expected {
            index += 1
            return true
        }
        return false
    }

    private func peek(ahead: Int = 0) -> Character? {
        let target = index + ahead
        guard target < input.count else { return nil }
        return input[target]
    }
}
