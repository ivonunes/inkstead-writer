import Foundation
import Plume

struct PlumeInlineResourceRenderer {
    struct ScriptOptions {
        var tagAttributes: String
        var source: (PlumeScriptResource) throws -> String
        var compile: (String, PlumeScriptResource) throws -> String

        init(
            tagAttributes: String = "",
            source: @escaping (PlumeScriptResource) throws -> String,
            compile: @escaping (String, PlumeScriptResource) throws -> String
        ) {
            self.tagAttributes = tagAttributes
            self.source = source
            self.compile = compile
        }
    }

    var styleError: String
    var script: ScriptOptions

    func inject(_ html: String, result: PlumeRenderResult) throws -> String {
        var output = try injectStyles(html, styles: result.styles)
        output = try injectScripts(output, scripts: result.scripts)
        return output
    }

    private func injectStyles(_ html: String, styles: [PlumeStyleResource]) throws -> String {
        guard !styles.isEmpty else { return html }
        let tags = try styles
            .map { style -> String in
                guard let css = style.css else {
                    throw InksteadWriterError.template(styleError)
                }
                return "<style>\n\(css)\n</style>"
            }
            .joined(separator: "\n")
        return HTMLInsertion.insert(tags + "\n", into: html, beforeClosingTag: "</head>")
    }

    private func injectScripts(_ html: String, scripts: [PlumeScriptResource]) throws -> String {
        guard !scripts.isEmpty else { return html }
        let attributes = script.tagAttributes.isEmpty ? "" : " \(script.tagAttributes)"
        let tags = try scripts
            .map { resource -> String in
                let source = try script.source(resource)
                let compiled = try script.compile(source, resource)
                return "<script\(attributes)>\n\(escapeScript(compiled))\n</script>"
            }
            .joined(separator: "\n")
        return HTMLInsertion.insert(tags + "\n", into: html, beforeClosingTag: "</body>")
    }

    private func escapeScript(_ js: String) -> String {
        js.replacingOccurrences(of: "</", with: "<\\/")
    }
}

enum HTMLInsertion {
    static func insert(_ content: String, into html: String, beforeClosingTag tag: String) -> String {
        if let range = html.range(of: tag, options: [.caseInsensitive, .backwards]) {
            var output = html
            output.insert(contentsOf: content, at: range.lowerBound)
            return output
        }
        return html + "\n" + content
    }
}
