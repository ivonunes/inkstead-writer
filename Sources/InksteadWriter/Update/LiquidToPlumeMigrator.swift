import Foundation

enum LiquidToPlumeMigrator {
    static func convert(_ source: String) throws -> String {
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            if source[index...].hasPrefix("{{") {
                let bodyStart = source.index(index, offsetBy: 2)
                guard let close = source[bodyStart...].range(of: "}}") else {
                    output += String(source[index...])
                    break
                }
                output += "{\(convertOutput(normalizeBody(source[bodyStart..<close.lowerBound])))}"
                index = close.upperBound
                continue
            }
            if source[index...].hasPrefix("{%") {
                let bodyStart = source.index(index, offsetBy: 2)
                guard let close = source[bodyStart...].range(of: "%}") else {
                    output += String(source[index...])
                    break
                }
                let tag = normalizeBody(source[bodyStart..<close.lowerBound])
                if tag == "comment" {
                    guard let end = source[close.upperBound...].range(of: #"\{%-?\s*endcomment\s*-?%\}"#, options: .regularExpression) else {
                        throw InksteadWriterError.template("Missing endcomment in legacy template.")
                    }
                    index = end.upperBound
                    continue
                }
                output += try convertTag(tag)
                index = close.upperBound
                continue
            }
            output.append(source[index])
            index = source.index(after: index)
        }
        return output
    }

    private static func normalizeBody(_ body: Substring) -> String {
        var text = String(body).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("-") {
            text.removeFirst()
        }
        if text.hasSuffix("-") {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func convertTag(_ tag: String) throws -> String {
        if tag.hasPrefix("assign ") {
            let source = String(tag.dropFirst("assign ".count))
            guard let equals = source.firstIndex(of: "=") else {
                throw InksteadWriterError.template("Invalid assign tag in legacy template.")
            }
            let name = source[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let expressionStart = source.index(after: equals)
            let expression = source[expressionStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            return "@let \(name) = \(convertExpression(expression, forOutput: false))\n"
        }
        if tag.hasPrefix("if ") {
            let condition = tag.dropFirst("if ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return "@if \(convertCondition(condition)) {\n"
        }
        if tag.hasPrefix("unless ") {
            let condition = tag.dropFirst("unless ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return "@if !(\(convertCondition(condition))) {\n"
        }
        if tag.hasPrefix("elsif ") {
            let condition = tag.dropFirst("elsif ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\n} else if \(convertCondition(condition)) {\n"
        }
        if tag == "else" {
            return "\n} else {\n"
        }
        if tag == "endif" || tag == "endunless" || tag == "endfor" {
            return "\n}\n"
        }
        if tag.hasPrefix("for ") {
            let source = String(tag.dropFirst("for ".count))
            guard let inRange = source.range(of: #"\s+in\s+"#, options: .regularExpression) else {
                throw InksteadWriterError.template("Invalid for tag in legacy template.")
            }
            let variable = source[..<inRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let collection = source[inRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return "@for \(variable) in \(convertExpression(collection, forOutput: false)) {\n"
        }
        if tag == "endcomment" {
            return ""
        }
        throw InksteadWriterError.template("Unsupported legacy template tag \(tag).")
    }

    private static func convertOutput(_ expression: String) -> String {
        convertExpression(expression, forOutput: true)
    }

    private static func convertCondition(_ expression: String) -> String {
        convertExpression(expression, forOutput: false)
    }

    private static func convertExpression(_ expression: String, forOutput: Bool) -> String {
        let segments = splitExpression(expression, separator: "|")
        guard let first = segments.first else { return "" }
        var converted = convertOperators(first)
        var escaped = false
        var raw = false
        for filter in segments.dropFirst() {
            let parsed = parseFilter(filter)
            let name = mappedFilterName(parsed.name)
            if name == "escape" || name == "escape_once" {
                escaped = true
                raw = false
                continue
            }
            if name == "raw" {
                raw = true
                continue
            }
            let arguments = parsed.arguments.map { convertExpression($0, forOutput: false) }.joined(separator: ", ")
            if name == "replace" || name == "replaceFirst" {
                converted += ".\(name)(\(arguments))"
            } else {
                converted += arguments.isEmpty ? " | \(name)" : " | \(name)(\(arguments))"
            }
        }
        if forOutput && !escaped && !raw {
            converted += " | raw"
        }
        return converted
    }

    private static func convertOperators(_ expression: String) -> String {
        let output = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if let logical = infix(output, operatorText: " or ") {
            return "\(convertOperators(logical.left)) || \(convertOperators(logical.right))"
        }
        if let logical = infix(output, operatorText: " and ") {
            return "\(convertOperators(logical.left)) && \(convertOperators(logical.right))"
        }
        if let contains = infix(output, operatorText: " contains ") {
            return "\(convertOperators(contains.left)).contains(\(convertOperators(contains.right)))"
        }
        return output
    }

    private static func parseFilter(_ filter: String) -> (name: String, arguments: [String]) {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else {
            return (trimmed, [])
        }
        let name = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let argumentStart = trimmed.index(after: colon)
        let arguments = splitExpression(String(trimmed[argumentStart...]), separator: ",")
        return (name, arguments)
    }

    private static func mappedFilterName(_ name: String) -> String {
        switch name {
        case "date_to_xmlschema": return "dateToXMLSchema"
        case "date_to_rfc822": return "dateToRFC822"
        case "date_to_string": return "dateToString"
        case "date_to_long_string": return "dateToLongString"
        case "divided_by": return "dividedBy"
        case "replace_first": return "replaceFirst"
        case "remove_first": return "removeFirst"
        case "strip_newlines": return "stripNewlines"
        case "newline_to_br": return "newlineToBR"
        case "strip_html": return "stripHTML"
        case "url_encode": return "urlEncode"
        case "url_decode": return "urlDecode"
        case "truncatewords": return "truncateWords"
        case "at_least": return "atLeast"
        case "at_most": return "atMost"
        case "sort_natural": return "sortNatural"
        case "uniq": return "unique"
        default: return name
        }
    }

    private static func splitExpression(_ expression: String, separator: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var parenDepth = 0
        var index = expression.startIndex
        while index < expression.endIndex {
            let character = expression[index]
            if let quoteCharacter = quote {
                current.append(character)
                if character == quoteCharacter { quote = nil }
                index = expression.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index = expression.index(after: index)
                continue
            }
            if character == "(" {
                parenDepth += 1
                current.append(character)
                index = expression.index(after: index)
                continue
            }
            if character == ")" {
                parenDepth = max(0, parenDepth - 1)
                current.append(character)
                index = expression.index(after: index)
                continue
            }
            if parenDepth == 0, expression[index...].hasPrefix(separator), !isLogicalPipe(in: expression, at: index, separator: separator) {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                index = expression.index(index, offsetBy: separator.count)
                continue
            }
            current.append(character)
            index = expression.index(after: index)
        }
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    private static func isLogicalPipe(in expression: String, at index: String.Index, separator: String) -> Bool {
        guard separator == "|" else { return false }
        let next = expression.index(after: index)
        if next < expression.endIndex, expression[next] == "|" { return true }
        if index > expression.startIndex {
            let previous = expression.index(before: index)
            if expression[previous] == "|" { return true }
        }
        return false
    }

    private static func infix(_ expression: String, operatorText: String) -> (left: String, right: String)? {
        var quote: Character?
        var parenDepth = 0
        var index = expression.startIndex
        while index < expression.endIndex {
            let character = expression[index]
            if let quoteCharacter = quote {
                if character == quoteCharacter { quote = nil }
                index = expression.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                index = expression.index(after: index)
                continue
            }
            if character == "(" {
                parenDepth += 1
                index = expression.index(after: index)
                continue
            }
            if character == ")" {
                parenDepth = max(0, parenDepth - 1)
                index = expression.index(after: index)
                continue
            }
            if parenDepth == 0, expression[index...].hasPrefix(operatorText) {
                let left = String(expression[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rightStart = expression.index(index, offsetBy: operatorText.count)
                let right = String(expression[rightStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (left, right)
            }
            index = expression.index(after: index)
        }
        return nil
    }
}
