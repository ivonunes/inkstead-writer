import Foundation
import Plume

extension ThemeRenderer {
    func injectPlumeAssetsIfNeeded(_ html: String, result: PlumeRenderResult) throws -> String {
        var output = try injectPlumeStylesIfNeeded(html, styles: result.styles)
        output = try injectPlumeRuntimeIfNeeded(output, result: result)
        output = try injectPlumeScriptsIfNeeded(output, scripts: result.scripts)
        return output
    }

    func injectPlumeStylesIfNeeded(_ html: String, styles: [PlumeStyleResource]) throws -> String {
        let hrefs = try emitPlumeStyles(styles)
        guard !hrefs.isEmpty else { return html }
        let links =
            hrefs
            .map { #"<link rel="stylesheet" href="\#($0)">"# }
            .joined(separator: "\n")
        if let range = html.range(of: "</head>", options: [.caseInsensitive, .backwards]) {
            var output = html
            output.insert(contentsOf: links + "\n", at: range.lowerBound)
            return output
        }
        return links + "\n" + html
    }

    func emitPlumeStyles(_ styles: [PlumeStyleResource]) throws -> [String] {
        var hrefs: [String] = []
        var seen = Set<String>()
        for style in styles {
            let cacheKey = styleCacheKey(style)
            if let cached = emittedStyleCache.value(for: cacheKey) {
                guard seen.insert(cached).inserted else { continue }
                hrefs.append(cached)
                continue
            }
            var css = try cssContent(for: style)
            if style.scoped, let attribute = style.scopeAttribute {
                css = PlumeCSSScoper.scope(css, attribute: attribute)
            }
            let data = Data(css.utf8)
            let hash = String(SHA256.hex(data).prefix(12))
            let baseName = styleBaseName(style)
            let fileName = "\(baseName)-\(hash).css"
            let href = "/assets/plume/\(fileName)"
            guard seen.insert(href).inserted else { continue }
            let output = dist.appendingPathComponent("assets/plume/\(fileName)")
            if !FileManager.default.fileExists(atPath: output.path) {
                try write(css, to: output)
            }
            emittedStyleCache.set(href, for: cacheKey)
            hrefs.append(href)
        }
        return hrefs
    }

    func cssContent(for style: PlumeStyleResource) throws -> String {
        if let css = style.css {
            return css
        }
        guard let file = style.file else {
            throw InksteadWriterError.template("@style must include a CSS block or file path.")
        }
        let url = try resolveStyleFile(file, sourceName: style.sourceName)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func resolveStyleFile(_ file: String, sourceName: String?) throws -> URL {
        try resolvePlumeResourceFile(
            file, sourceName: sourceName, directive: "@style", kind: "style")
    }

    func styleBaseName(_ style: PlumeStyleResource) -> String {
        if let file = style.file {
            let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            return slugifyAssetName(name.isEmpty ? "style" : name)
        }
        if let sourceName = style.sourceName {
            let name = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
            return slugifyAssetName(name.isEmpty ? "style" : name)
        }
        return "style"
    }

    func styleCacheKey(_ style: PlumeStyleResource) -> String {
        [
            style.sourceName ?? "",
            style.file ?? "",
            style.css ?? "",
            style.scoped ? "scoped" : "global",
            style.scopeAttribute ?? "",
        ].joined(separator: "\u{1F}")
    }

    func slugifyAssetName(_ name: String, fallback: String = "style") -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? fallback : slug
    }

    func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func injectPlumeRuntimeIfNeeded(_ html: String, result: PlumeRenderResult) throws -> String {
        guard result.requiresRuntime else { return html }
        try writePlumeRuntimeIfNeeded()
        let data = try JSONSerialization.data(
            withJSONObject: jsonReady(result.state), options: [.sortedKeys])
        let json = (String(data: data, encoding: .utf8) ?? "{}").replacingOccurrences(
            of: "</", with: "<\\/")
        let navigationScripts = try plumeNavigationScripts(result.navigation)
        let scripts = #"""
            <script type="application/json" data-plume-state>\#(json)</script>
            \#(navigationScripts)
            <script src="/assets/plume-runtime.js" defer></script>
            """#
        if let range = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            var output = html
            output.insert(contentsOf: scripts + "\n", at: range.lowerBound)
            return output
        }
        return html + "\n" + scripts + "\n"
    }

    func writePlumeRuntimeIfNeeded() throws {
        let output = dist.appendingPathComponent("assets/plume-runtime.js")
        guard !FileManager.default.fileExists(atPath: output.path) else { return }
        try write(PlumeBrowserRuntime.javaScript, to: output)
    }

    func plumeNavigationScripts(_ navigation: [PlumeNavigationResource]) throws -> String {
        guard !navigation.isEmpty else { return "" }
        let values = navigation.map { resource in
            [
                "root": resource.root,
                "viewTransitions": resource.viewTransitions,
                "scroll": resource.scroll,
                "minimumDuration": resource.minimumDuration,
                "hooks": Dictionary(grouping: resource.hooks, by: \.name).mapValues { hooks in
                    hooks.flatMap(\.actions)
                },
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return
            #"<script type="application/json" data-plume-navigation>\#((String(data: data, encoding: .utf8) ?? "[]").replacingOccurrences(of: "</", with: "<\\/"))</script>"#
    }

    func injectPlumeScriptsIfNeeded(_ html: String, scripts: [PlumeScriptResource]) throws -> String
    {
        let srcs = try emitPlumeScripts(scripts)
        guard !srcs.isEmpty else { return html }
        let tags =
            srcs
            .map { #"<script type="module" src="\#($0)" defer></script>"# }
            .joined(separator: "\n")
        if let range = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            var output = html
            output.insert(contentsOf: tags + "\n", at: range.lowerBound)
            return output
        }
        return html + "\n" + tags + "\n"
    }

    func emitPlumeScripts(_ scripts: [PlumeScriptResource]) throws -> [String] {
        var srcs: [String] = []
        var seen = Set<String>()
        for script in scripts {
            let cacheKey = scriptCacheKey(script)
            if let cached = emittedScriptCache.value(for: cacheKey) {
                guard seen.insert(cached).inserted else { continue }
                srcs.append(cached)
                continue
            }
            var js = try jsContent(for: script)
            if script.scoped, let attribute = script.scopeAttribute {
                js = scopedScript(js, attribute: attribute)
            }
            let data = Data(js.utf8)
            let hash = String(SHA256.hex(data).prefix(12))
            let baseName = scriptBaseName(script)
            let fileName = "\(baseName)-\(hash).js"
            let src = "/assets/plume/\(fileName)"
            guard seen.insert(src).inserted else { continue }
            let output = dist.appendingPathComponent("assets/plume/\(fileName)")
            if !FileManager.default.fileExists(atPath: output.path) {
                try write(js, to: output)
            }
            emittedScriptCache.set(src, for: cacheKey)
            srcs.append(src)
        }
        return srcs
    }

    func jsContent(for script: PlumeScriptResource) throws -> String {
        let source: String
        if let js = script.js {
            source = js
        } else {
            guard let file = script.file else {
                throw InksteadWriterError.template(
                    "@script must include a JavaScript block or file path.")
            }
            let url = try resolveScriptFile(file, sourceName: script.sourceName)
            source = try String(contentsOf: url, encoding: .utf8)
        }
        switch script.language {
        case .javascript:
            return source
        case .plume:
            do {
                return try PlumeClientScriptCompiler.compile(source, sourceName: script.sourceName)
            } catch {
                throw InksteadWriterError.template(String(describing: error))
            }
        }
    }

    func resolveScriptFile(_ file: String, sourceName: String?) throws -> URL {
        try resolvePlumeResourceFile(
            file, sourceName: sourceName, directive: "@script", kind: "script")
    }

    func resolvePlumeResourceFile(
        _ file: String, sourceName: String?, directive: String, kind: String
    ) throws -> URL {
        let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InksteadWriterError.template("\(directive) file path cannot be empty.")
        }
        let sourceURL = sourceName.flatMap { URL(fileURLWithPath: $0) }
        var candidates: [URL] = []
        if let sourceURL, sourceURL.path.hasPrefix(root.path),
            FileManager.default.fileExists(atPath: sourceURL.path)
        {
            candidates.append(sourceURL.deletingLastPathComponent().appendingPathComponent(trimmed))
        }
        candidates.append(
            root.appendingPathComponent(config.theme?.path ?? "theme").appendingPathComponent(
                trimmed))
        candidates.append(root.appendingPathComponent(trimmed))
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw InksteadWriterError.template("Plume \(kind) file \(file) was not found.")
    }

    func scriptBaseName(_ script: PlumeScriptResource) -> String {
        if let file = script.file {
            let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            return slugifyAssetName(name.isEmpty ? "script" : name, fallback: "script")
        }
        if let sourceName = script.sourceName {
            let name = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
            return slugifyAssetName(name.isEmpty ? "script" : name, fallback: "script")
        }
        return "script"
    }

    func scriptCacheKey(_ script: PlumeScriptResource) -> String {
        [
            script.sourceName ?? "",
            script.file ?? "",
            script.js ?? "",
            String(describing: script.language),
            script.scoped ? "scoped" : "global",
            script.scopeAttribute ?? "",
        ].joined(separator: "\u{1F}")
    }

    func scopedScript(_ js: String, attribute: String) -> String {
        let body = indentJavaScript(js)
        return """
            let selector = "[\(attribute)]";
            for (let root of document.querySelectorAll(selector)) {
              if (root.parentElement && root.parentElement.closest(selector)) continue;
              void (async function(root) {
            \(body)
              })(root);
            }
            """
    }

    func indentJavaScript(_ js: String) -> String {
        js.components(separatedBy: .newlines)
            .map { $0.isEmpty ? "" : "    \($0)" }
            .joined(separator: "\n")
    }
}
