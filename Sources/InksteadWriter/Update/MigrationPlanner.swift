import Foundation

struct VersionedMigration {
    let version: InksteadWriterVersion
    let actions: (URL, InksteadWriterConfig) throws -> [MigrationAction]
}

public enum MigrationPlanner {
    public static func plan(root: URL, config: InksteadWriterConfig, targetVersion: String = InksteadWriterMetadata.currentVersion) throws -> MigrationPlan {
        let current = config.recordedVersion
        let currentVersion = InksteadWriterVersion(current)
        let target = InksteadWriterVersion(targetVersion)
        guard currentVersion <= target else {
            throw InksteadWriterError.config("This site was created with Inkstead Writer \(current). Install a newer Inkstead Writer binary before migrating it.")
        }
        var actions: [MigrationAction] = []
        var migrationActions: [MigrationAction] = []
        for migration in migrations where currentVersion < migration.version && migration.version <= target {
            migrationActions.append(contentsOf: try migration.actions(root, config))
        }
        actions.append(contentsOf: migrationActions)
        actions.append(contentsOf: try siteSupportActions(root: root))
        actions.append(contentsOf: try workflowActions(root: root, config: config))
        if !migrationActions.contains(where: \.isManual) {
            actions.append(contentsOf: try versionStampActions(root: root, config: config, targetVersion: targetVersion))
        }
        return MigrationPlan(currentVersion: current, targetVersion: targetVersion, actions: actions)
    }

    public static func apply(_ plan: MigrationPlan, root: URL) throws -> [String] {
        var changed: [String] = []
        for action in plan.actions {
            switch action {
            case .rename(let from, let to):
                let source = root.appendingPathComponent(from)
                let destination = root.appendingPathComponent(to)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    throw InksteadWriterError.io("\(to) already exists.")
                }
                try FileManager.default.moveItem(at: source, to: destination)
                changed.append("\(from) -> \(to)")
            case .delete(let path):
                let url = root.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    changed.append(path)
                }
            case .write(let path, let content, _):
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                if path == SiteWrapper.path {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                changed.append(path)
            case .manual:
                continue
            }
        }
        return changed
    }

    private static var migrations: [VersionedMigration] {
        [
            VersionedMigration(version: InksteadWriterVersion("2.0.0")) { root, config in
                try legacyTemplateToPlumeActions(root: root, config: config)
            }
        ]
    }

    private static func legacyTemplateToPlumeActions(root: URL, config: InksteadWriterConfig) throws -> [MigrationAction] {
        let themeDir = root.appendingPathComponent(config.theme?.path ?? "theme")
        guard FileManager.default.fileExists(atPath: themeDir.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(at: themeDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var actions: [MigrationAction] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "liquid" else { continue }
            let relative = relativePath(file, root: root)
            let destination = file.deletingPathExtension().appendingPathExtension("plume")
            let destinationRelative = (relative as NSString).deletingPathExtension + ".plume"
            if FileManager.default.fileExists(atPath: destination.path) {
                actions.append(.manual(path: relative, message: "\(destinationRelative) already exists; review and merge this legacy template manually."))
                continue
            }
            let source = try String(contentsOf: file, encoding: .utf8)
            if let unsupported = unsupportedLiquidConstruct(in: source) {
                actions.append(.manual(path: relative, message: "Unsupported legacy template construct \(unsupported); convert this template manually."))
                continue
            }
            if let unsupported = unsupportedLiquidFilter(in: source) {
                actions.append(.manual(path: relative, message: "Unsupported legacy template filter \(unsupported); convert this template manually."))
                continue
            }
            actions.append(.write(path: destinationRelative, content: try LiquidToPlumeMigrator.convert(source), reason: "convert legacy template to Plume"))
            actions.append(.delete(path: relative))
        }
        return actions.sorted { $0.description < $1.description }
    }

    private static func versionStampActions(root: URL, config: InksteadWriterConfig, targetVersion: String) throws -> [MigrationAction] {
        let currentJSON = root.appendingPathComponent(InksteadWriterMetadata.configFileName)
        let legacyJSON = root.appendingPathComponent(InksteadWriterMetadata.legacyConfigFileName)
        if FileManager.default.fileExists(atPath: currentJSON.path) || FileManager.default.fileExists(atPath: legacyJSON.path) {
            let migrated = try migratedConfig(root: root, config: config, targetVersion: targetVersion)
            let content = try encodeConfig(migrated)
            var actions: [MigrationAction] = []
            if !FileManager.default.fileExists(atPath: currentJSON.path)
                || (try? String(contentsOf: currentJSON, encoding: .utf8)) != content {
                actions.append(.write(
                    path: InksteadWriterMetadata.configFileName,
                    content: content,
                    reason: "record Inkstead Writer version \(targetVersion)"
                ))
            }
            if FileManager.default.fileExists(atPath: legacyJSON.path) {
                actions.append(.delete(path: InksteadWriterMetadata.legacyConfigFileName))
            }
            return actions
        }

        let tsURL = root.appendingPathComponent("site.config.ts")
        guard FileManager.default.fileExists(atPath: tsURL.path) else { return [] }
        let migrated = try migratedConfig(root: root, config: config, targetVersion: targetVersion)
        return [
            .write(
                path: InksteadWriterMetadata.configFileName,
                content: try encodeConfig(migrated),
                reason: "migrate TypeScript config to versioned JSON"
            ),
            .manual(path: "site.config.ts", message: "Review the generated \(InksteadWriterMetadata.configFileName), then remove site.config.ts.")
        ]
    }

    private static func encodeConfig(_ config: InksteadWriterConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    private static func migratedConfig(root: URL, config: InksteadWriterConfig, targetVersion: String) throws -> InksteadWriterConfig {
        var migrated = config
        migrated.legacyInkstead = nil
        migrated.version = targetVersion
        if let connection = try legacyAppConnection(root: root) {
            migrated.connection = connection
        }
        return migrated
    }

    private static func legacyAppConnection(root: URL) throws -> AppConnectionConfig? {
        for name in [InksteadWriterMetadata.configFileName, InksteadWriterMetadata.legacyConfigFileName] {
            let url = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let writer = object["writer"] as? [String: Any],
                  let legacy = writer["editor"] as? [String: Any] else {
                continue
            }
            let repository = string(legacy["repository"]) ?? legacyRepository(owner: string(legacy["owner"]), repo: string(legacy["repo"]))
            let provider = string(legacy["provider"]).flatMap(AppConnectionProviderName.init(rawValue:))
            let categories = legacy["categories"] as? [String]
            let branch = string(legacy["branch"])
            let instanceUrl = string(legacy["instanceUrl"])
            if provider == nil, repository == nil, branch == nil, instanceUrl == nil, categories?.isEmpty != false {
                return nil
            }
            return AppConnectionConfig(
                provider: provider,
                repository: repository,
                branch: branch,
                instanceUrl: instanceUrl,
                categories: categories
            )
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func legacyRepository(owner: String?, repo: String?) -> String? {
        guard let owner, let repo else { return nil }
        return "\(owner)/\(repo)"
    }

    private static func workflowActions(root: URL, config: InksteadWriterConfig) throws -> [MigrationAction] {
        guard let file = AdapterSupport.workflowFile(config: config) else { return [] }
        let url = root.appendingPathComponent(file.path)
        if !FileManager.default.fileExists(atPath: url.path) {
            return [.write(path: file.path, content: file.content, reason: "create generated workflow")]
        }
        let current = try String(contentsOf: url, encoding: .utf8)
        if current != file.content {
            return [.write(path: file.path, content: file.content, reason: "refresh generated workflow")]
        }
        return []
    }

    private static func siteSupportActions(root: URL) throws -> [MigrationAction] {
        var actions: [MigrationAction] = []
        let wrapperURL = root.appendingPathComponent(SiteWrapper.path)
        let wrapperNeedsUpdate: Bool
        if FileManager.default.fileExists(atPath: wrapperURL.path) {
            wrapperNeedsUpdate = try String(contentsOf: wrapperURL, encoding: .utf8) != SiteWrapper.script
        } else {
            wrapperNeedsUpdate = true
        }
        if wrapperNeedsUpdate {
            actions.append(.write(path: SiteWrapper.path, content: SiteWrapper.script, reason: "install versioned Inkstead Writer wrapper"))
        }
        let legacyWrapperURL = root.appendingPathComponent("inkstead")
        if SiteWrapper.path != "inkstead", FileManager.default.fileExists(atPath: legacyWrapperURL.path) {
            actions.append(.delete(path: "inkstead"))
        }
        return actions
    }

    private static func unsupportedLiquidConstruct(in source: String) -> String? {
        let supported = Set(["assign", "comment", "endcomment", "if", "elsif", "else", "endif", "unless", "endunless", "for", "endfor"])
        guard let regex = try? NSRegularExpression(pattern: #"\{%-?\s*([A-Za-z_][A-Za-z0-9_]*)"#) else { return nil }
        let ns = source as NSString
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1))
            if !supported.contains(tag) { return tag }
        }
        return nil
    }

    private static func unsupportedLiquidFilter(in source: String) -> String? {
        let supported = Set([
            "abs", "append", "at_least", "at_most", "capitalize", "ceil", "compact", "concat", "date",
            "date_to_long_string", "date_to_rfc822", "date_to_string", "date_to_xmlschema", "default",
            "divided_by", "downcase", "escape", "escape_once", "first", "floor", "join", "last", "lstrip",
            "map", "minus", "modulo", "newline_to_br", "plus", "prepend", "raw", "remove", "remove_first",
            "replace", "replace_first", "reverse", "round", "rstrip", "size", "slice", "slug", "slugify",
            "sort", "sort_natural", "split", "strip", "strip_html", "strip_newlines", "times", "truncate",
            "truncatewords", "uniq", "upcase", "url_decode", "url_encode", "where"
        ])
        guard let variableRegex = try? NSRegularExpression(pattern: #"\{\{-?\s*([\s\S]*?)\s*-?\}\}"#) else { return nil }
        let ns = source as NSString
        for variableMatch in variableRegex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let expression = ns.substring(with: variableMatch.range(at: 1))
            for filter in filterNames(in: expression) {
                if !supported.contains(filter) { return filter }
            }
        }
        return nil
    }

    private static func filterNames(in expression: String) -> [String] {
        var names: [String] = []
        var quote: Character?
        var index = expression.startIndex
        while index < expression.endIndex {
            let char = expression[index]
            if let quoteChar = quote {
                if char == quoteChar { quote = nil }
                index = expression.index(after: index)
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                index = expression.index(after: index)
                continue
            }
            guard char == "|" else {
                index = expression.index(after: index)
                continue
            }
            index = expression.index(after: index)
            while index < expression.endIndex, expression[index].isWhitespace {
                index = expression.index(after: index)
            }
            let start = index
            while index < expression.endIndex {
                let current = expression[index]
                if !(current.isLetter || current.isNumber || current == "_") { break }
                index = expression.index(after: index)
            }
            if start < index {
                names.append(String(expression[start..<index]))
            }
        }
        return names
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPaths = [
            root.standardizedFileURL.path,
            root.resolvingSymlinksInPath().standardizedFileURL.path
        ]
        let paths = [
            url.standardizedFileURL.path,
            url.resolvingSymlinksInPath().standardizedFileURL.path
        ]
        for path in paths {
            for rootPath in rootPaths where path.hasPrefix(rootPath) {
                return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        return url.lastPathComponent
    }
}
