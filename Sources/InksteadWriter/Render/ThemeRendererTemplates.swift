import Foundation
import Plume

extension ThemeRenderer {
    func loadTemplate(_ name: String) throws -> String {
        for plume in templateCandidates(for: name) {
            if let template = themeTemplates[templateKey(plume)] {
                return template
            }
        }
        for liquid in legacyTemplateCandidates(for: name) where legacyTemplatePaths.contains(templateKey(liquid)) {
            throw InksteadWriterError.template("Legacy Liquid template \(liquid.lastPathComponent) is no longer loaded. Run ./inkstead-writer migrate to convert templates to Plume.")
        }
        guard let template = DefaultTemplates.templates[name] else {
            throw InksteadWriterError.template("Template \(name) was not found.")
        }
        return template
    }

    func templatePath(_ name: String) -> String {
        for plume in templateCandidates(for: name) where themeTemplates[templateKey(plume)] != nil {
            return plume.path
        }
        return "DefaultTemplates/\(name).plume"
    }

    static func loadComponents(root: URL, config: InksteadWriterConfig) throws -> [String: String] {
        var components = DefaultTemplates.components
        let componentsDir = themeRoot(root: root, config: config).appendingPathComponent("components")
        guard FileManager.default.fileExists(atPath: componentsDir.path),
              let enumerator = FileManager.default.enumerator(at: componentsDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return components
        }
        for case let file as URL in enumerator where file.pathExtension == "plume" {
            components[file.path] = try String(contentsOf: file, encoding: .utf8)
        }
        return components
    }

    func customTemplateExists(_ name: String) throws -> Bool {
        if templateCandidates(for: name).contains(where: { themeTemplates[templateKey($0)] != nil }) {
            return true
        }
        for liquid in legacyTemplateCandidates(for: name) where legacyTemplatePaths.contains(templateKey(liquid)) {
            throw InksteadWriterError.template("Legacy Liquid template \(liquid.lastPathComponent) is no longer loaded. Run ./inkstead-writer migrate to convert templates to Plume.")
        }
        return false
    }

    func templateCandidates(for name: String) -> [URL] {
        let themeDir = ThemeRenderer.themeRoot(root: root, config: config)
        if name == "layout" {
            return [
                themeDir.appendingPathComponent("layouts/default.plume"),
                themeDir.appendingPathComponent("layouts/layout.plume"),
                themeDir.appendingPathComponent("layout.plume")
            ]
        }
        return [
            themeDir.appendingPathComponent("pages/\(name).plume"),
            themeDir.appendingPathComponent("\(name).plume")
        ]
    }

    func legacyTemplateCandidates(for name: String) -> [URL] {
        templateCandidates(for: name).map { $0.deletingPathExtension().appendingPathExtension("liquid") }
    }

    static func loadThemeTemplates(root: URL, config: InksteadWriterConfig) throws -> [String: String] {
        let themeDir = themeRoot(root: root, config: config)
        guard FileManager.default.fileExists(atPath: themeDir.path),
              let enumerator = FileManager.default.enumerator(at: themeDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        var templates: [String: String] = [:]
        for case let file as URL in enumerator where file.pathExtension == "plume" {
            templates[templateKey(file)] = try String(contentsOf: file, encoding: .utf8)
        }
        return templates
    }

    static func loadLegacyTemplatePaths(root: URL, config: InksteadWriterConfig) throws -> Set<String> {
        let themeDir = themeRoot(root: root, config: config)
        guard FileManager.default.fileExists(atPath: themeDir.path),
              let enumerator = FileManager.default.enumerator(at: themeDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var paths = Set<String>()
        for case let file as URL in enumerator where file.pathExtension == "liquid" {
            paths.insert(templateKey(file))
        }
        return paths
    }

    static func themeRoot(root: URL, config: InksteadWriterConfig) -> URL {
        root.appendingPathComponent(config.theme?.path ?? "theme")
    }

    static func templateKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    func templateKey(_ url: URL) -> String {
        ThemeRenderer.templateKey(url)
    }

    func mergedRenderResult(_ first: PlumeRenderResult, _ second: PlumeRenderResult) -> PlumeRenderResult {
        var state = first.state
        for (key, value) in second.state {
            state[key] = value
        }
        return PlumeRenderResult(
            html: second.html,
            requiresRuntime: first.requiresRuntime || second.requiresRuntime,
            state: state,
            styles: second.styles + first.styles,
            scripts: second.scripts + first.scripts,
            navigation: second.navigation + first.navigation
        )
    }
}
