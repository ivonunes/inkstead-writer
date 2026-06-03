import Foundation

public struct ThemeEjectResult: Equatable {
    public var copied: [String]
    public var skipped: [String]

    public init(copied: [String], skipped: [String]) {
        self.copied = copied
        self.skipped = skipped
    }
}

public enum ThemeEjector {
    public static func eject(root: URL, themePath: String = "theme", force: Bool = false) throws -> ThemeEjectResult {
        let themeDir = root.appendingPathComponent(themePath)
        try FileManager.default.createDirectory(at: themeDir, withIntermediateDirectories: true)

        var copied: [String] = []
        var skipped: [String] = []

        for name in DefaultTemplates.names {
            let fileName = DefaultTemplates.organizedFileName(for: name)
            let flatFileName = DefaultTemplates.fileName(for: name)
            let relativePath = "\(themePath)/\(fileName)"
            let destination = themeDir.appendingPathComponent(fileName)
            let flatDestination = themeDir.appendingPathComponent(flatFileName)

            if !force && (FileManager.default.fileExists(atPath: destination.path) || FileManager.default.fileExists(atPath: flatDestination.path)) {
                skipped.append(relativePath)
                continue
            }

            guard let template = DefaultTemplates.templates[name] else {
                throw InksteadWriterError.template("Default template \(name) was not found.")
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try template.write(to: destination, atomically: true, encoding: .utf8)
            copied.append(relativePath)
        }

        for (sourceName, component) in DefaultTemplates.components.sorted(by: { $0.key < $1.key }) {
            let fileName = sourceName.replacingOccurrences(of: "DefaultTemplates/", with: "")
            let relativePath = "\(themePath)/\(fileName)"
            let destination = themeDir.appendingPathComponent(fileName)

            if !force && FileManager.default.fileExists(atPath: destination.path) {
                skipped.append(relativePath)
                continue
            }

            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try component.write(to: destination, atomically: true, encoding: .utf8)
            copied.append(relativePath)
        }

        return ThemeEjectResult(copied: copied, skipped: skipped)
    }
}
