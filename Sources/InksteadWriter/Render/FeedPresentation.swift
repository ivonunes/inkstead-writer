import Foundation
import Plume

struct FeedPresentation {
    var scriptSrc: String
    var styleHrefs: [String]
}

extension ThemeRenderer {
    func xmlFeed(posts: [NormalizedPost], title: String? = nil, path: String = "/feed.xml", category: CategoryCollection? = nil) throws -> String {
        let initial = try renderXMLFeed(posts: posts, title: title, path: path, presentationScriptSrc: "", category: category)
        let presentation = try feedPresentation(from: initial.result)
        let final = try renderXMLFeed(
            posts: posts,
            title: title,
            path: path,
            presentationScriptSrc: presentation?.scriptSrc ?? "",
            presentationStyleHrefs: presentation?.styleHrefs ?? [],
            category: category
        )
        return final.result.html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func jsonFeed(posts: [NormalizedPost], title: String? = nil, path: String = "/feed.json", category: CategoryCollection? = nil) throws -> String {
        var context = baseContext()
        context["feed"] = FeedRenderer.jsonContext(config: config, posts: posts, title: title, path: path, category: category.map(serializedCategory))
        let result = try plumeTemplate("feed.json").renderResult(context)
        guard !result.requiresRuntime, result.state.isEmpty, result.navigation.isEmpty, result.styles.isEmpty, result.scripts.isEmpty else {
            throw InksteadWriterError.template("feed.json.plume renders JSON and cannot use Plume runtime state, actions, navigation, styles, or scripts.")
        }
        return result.html
    }

    private func renderXMLFeed(
        posts: [NormalizedPost],
        title: String?,
        path: String,
        presentationScriptSrc: String,
        presentationStyleHrefs: [String] = [],
        category: CategoryCollection?
    ) throws -> (result: PlumeRenderResult, context: [String: Any]) {
        var context = baseContext()
        context["feed"] = FeedRenderer.rssContext(
            config: config,
            posts: posts,
            title: title,
            path: path,
            presentationScriptSrc: presentationScriptSrc,
            presentationStyleHrefs: presentationStyleHrefs,
            category: category.map(serializedCategory)
        )
        let result = try plumeTemplate("feed.xml").renderResult(context)
        guard !result.requiresRuntime, result.state.isEmpty, result.navigation.isEmpty else {
            throw InksteadWriterError.template("feed.xml.plume renders RSS XML and cannot use Plume runtime state, actions, or navigation.")
        }
        return (result, context)
    }

    private func feedPresentation(from result: PlumeRenderResult) throws -> FeedPresentation? {
        let styleHrefs = try emitPlumeStyles(result.styles)
        let scripts = try result.scripts.map(feedScriptContent)
        guard !styleHrefs.isEmpty || !scripts.isEmpty else {
            return nil
        }

        let js = try feedPresentationJavaScript(styleHrefs: styleHrefs, scripts: scripts)
        let data = Data(js.utf8)
        let hash = String(SHA256.hex(data).prefix(12))
        let src = "/assets/plume/feed-\(hash).js"
        let output = dist.appendingPathComponent("assets/plume/feed-\(hash).js")
        if !FileManager.default.fileExists(atPath: output.path) {
            try write(js, to: output)
        }
        return FeedPresentation(scriptSrc: src, styleHrefs: styleHrefs)
    }

    private func feedScriptContent(_ script: PlumeScriptResource) throws -> String {
        var js = try jsContent(for: script)
        if script.scoped, let attribute = script.scopeAttribute {
            js = scopedScript(js, attribute: attribute)
        }
        return js
    }

    private func feedPresentationJavaScript(styleHrefs: [String], scripts: [String]) throws -> String {
        let payload: [String: Any] = [
            "styles": styleHrefs
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = (String(data: data, encoding: .utf8) ?? #"{"styles":[]}"#)
            .replacingOccurrences(of: "</", with: "<\\/")
        let scriptBody = scripts.joined(separator: "\n\n")
        return """
        (function() {
          window.PlumeFeed = Object.assign(window.PlumeFeed || {}, \(json));
        })();

        \(scriptBody)
        """
    }
}
