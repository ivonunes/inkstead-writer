import Foundation

public struct DoctorResult: Equatable {
    public var output: String
    public var issues: Int
}

public enum Doctor {
    public static func run(root: URL, config: InksteadWriterConfig, env: [String: String] = ProcessInfo.processInfo.environment) -> DoctorResult {
        var groups: [(String, [DoctorCheck])] = []
        let jsonConfigFound = FileManager.default.fileExists(atPath: root.appendingPathComponent(InksteadWriterMetadata.configFileName).path)
        let legacyJSONConfigFound = FileManager.default.fileExists(atPath: root.appendingPathComponent(InksteadWriterMetadata.legacyConfigFileName).path)
        let tsConfigFound = FileManager.default.fileExists(atPath: root.appendingPathComponent("site.config.ts").path)
        let configFound = jsonConfigFound || legacyJSONConfigFound || tsConfigFound
        let configLabel = jsonConfigFound ? "\(InksteadWriterMetadata.configFileName) found" : legacyJSONConfigFound ? "\(InksteadWriterMetadata.legacyConfigFileName) found" : "site.config.ts found"
        var core = [
            DoctorCheck(status: configFound ? .pass : .fail, label: configFound ? configLabel : "Inkstead Writer config missing")
        ]
        for dir in [config.content.posts, config.content.pages, config.content.media] {
            core.append(DoctorCheck(status: FileManager.default.fileExists(atPath: root.appendingPathComponent(dir).path) ? .pass : .fail, label: "\(dir) found"))
        }
        groups.append(("Core", core))

        var environment = [
            DoctorCheck(status: FileManager.default.fileExists(atPath: root.appendingPathComponent(".env").path) ? .pass : .warn, label: FileManager.default.fileExists(atPath: root.appendingPathComponent(".env").path) ? ".env loaded" : ".env not found")
        ]
        let mergedEnv = EnvFile.read(root: root).merging(env) { _, new in new }
        for requirement in AdapterSupport.requirements(for: config) {
            let set = !(mergedEnv[requirement.environmentVariable]?.isEmpty ?? true)
            environment.append(DoctorCheck(status: set ? .pass : .fail, label: "\(requirement.environmentVariable) is \(set ? "set" : "missing")"))
        }
        groups.append(("Environment", environment))

        let adapterChecks = AdapterSupport.adapterChecks(root: root, config: config, env: mergedEnv)
        if !adapterChecks.isEmpty {
            groups.append(("Adapters", adapterChecks))
        }

        let launcher = launcherChecks(root: root, config: config)
        if !launcher.isEmpty {
            groups.append(("Launcher", launcher))
        }

        if let workflow = AdapterSupport.workflowFile(config: config) {
            let url = root.appendingPathComponent(workflow.path)
            if FileManager.default.fileExists(atPath: url.path), (try? String(contentsOf: url, encoding: .utf8)) != workflow.content {
                groups.append(("Generated Files", [DoctorCheck(status: .warn, label: "\(workflow.path) differs from Inkstead Writer's current template", message: "run ./inkstead-writer migrate")]))
            }
        }

        let content: [DoctorCheck]
        do {
            _ = try ContentLoader.loadPosts(root: root, config: config)
            content = [DoctorCheck(status: .pass, label: "content loaded")]
        } catch {
            content = [DoctorCheck(status: .fail, label: error is InksteadWriterError ? String(describing: error) : error.localizedDescription)]
        }
        groups.append(("Content", content))

        let checks = groups.flatMap(\.1)
        let issues = checks.filter { $0.status == .fail }.count
        let warnings = checks.filter { $0.status == .warn }.count
        let passed = checks.filter { $0.status == .pass }.count
        var lines = [
            "Inkstead Writer Doctor",
            "",
            "Summary",
            "  ✓  \(plural(passed, "check")) passed",
            "  !  \(plural(warnings, "warning"))",
            "  ×  \(plural(issues, "issue"))",
            ""
        ]
        for (title, checks) in groups {
            lines.append(title)
            lines.append(contentsOf: checks.map(renderCheck))
            lines.append("")
        }
        lines.append("Result")
        lines.append(issues == 0 ? "No blocking issues found." : "\(plural(issues, "blocking issue")) found.")
        return DoctorResult(output: lines.joined(separator: "\n") + "\n", issues: issues)
    }

    private static func launcherChecks(root: URL, config: InksteadWriterConfig) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        let wrapper = root.appendingPathComponent(SiteWrapper.path)
        if FileManager.default.fileExists(atPath: wrapper.path) {
            checks.append(DoctorCheck(
                status: FileManager.default.isExecutableFile(atPath: wrapper.path) ? .pass : .warn,
                label: FileManager.default.isExecutableFile(atPath: wrapper.path) ? "\(SiteWrapper.path) is executable" : "\(SiteWrapper.path) is not executable",
                message: FileManager.default.isExecutableFile(atPath: wrapper.path) ? nil : "run ./inkstead-writer migrate"
            ))
            let content = (try? String(contentsOf: wrapper, encoding: .utf8)) ?? ""
            checks.append(DoctorCheck(
                status: content == SiteWrapper.script ? .pass : .warn,
                label: content == SiteWrapper.script ? "\(SiteWrapper.path) wrapper is current" : "\(SiteWrapper.path) wrapper differs from Inkstead Writer's current template",
                message: content == SiteWrapper.script ? nil : "run ./inkstead-writer migrate"
            ))
        } else {
            checks.append(DoctorCheck(status: .warn, label: "\(SiteWrapper.path) wrapper missing", message: "run ./inkstead-writer migrate"))
        }

        if let workflow = AdapterSupport.workflowFile(config: config) {
            let workflowURL = root.appendingPathComponent(workflow.path)
            if let workflowContents = try? String(contentsOf: workflowURL, encoding: .utf8),
               workflowContents.contains("inkstead-writer publish"),
               !workflowContents.contains("./inkstead-writer publish") {
                checks.append(DoctorCheck(status: .warn, label: "\(workflow.path) runs global inkstead-writer", message: "run ./inkstead-writer migrate"))
            }
        }

        return checks
    }

    private static func renderCheck(_ check: DoctorCheck) -> String {
        let marker = check.status == .pass ? "✓" : check.status == .warn ? "!" : "×"
        return "  \(marker)  \(check.label)\(check.message.map { " (\($0))" } ?? "")"
    }

    private static func plural(_ count: Int, _ singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}
