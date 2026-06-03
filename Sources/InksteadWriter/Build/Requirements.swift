import Foundation

public enum RequirementsRenderer {
    public static func render(_ config: InksteadWriterConfig) -> String {
        let syndication = config.syndication?.providers ?? []
        let requirements = AdapterSupport.requirements(for: config)
        var lines = ["Inkstead Writer Requirements", ""]
        lines.append("Configured Adapters")
        lines.append(row("CI", AdapterSupport.ciName(config.ci?.provider)))
        lines.append(row("Deployment", AdapterSupport.deployName(config.deploy?.provider)))
        lines.append(row("Syndication", syndication.isEmpty ? "None" : syndication.map(AdapterSupport.syndicationName).joined(separator: ", ")))
        lines.append("")
        lines.append("Environment Variables")
        if requirements.isEmpty {
            lines.append("  No local environment variables are required.")
        } else {
            let width = requirements.map(\.environmentVariable.count).max() ?? 0
            for requirement in requirements {
                lines.append("  \(requirement.environmentVariable.padding(toLength: width, withPad: " ", startingAt: 0))  \(requirement.description.trimmingSuffix("."))")
            }
            lines.append("")
            lines.append("Local Publishing")
            lines.append("  cp .env.example .env")
            lines.append("  Fill in the values, then run ./inkstead-writer doctor.")
            lines.append("")
            lines.append("CI Publishing")
            lines.append("  Add the same names from .env.example as secrets or variables.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ label: String, _ value: String) -> String {
        "  \(label.padding(toLength: 14, withPad: " ", startingAt: 0)) \(value)"
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
