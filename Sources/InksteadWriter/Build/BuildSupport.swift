import Foundation

public enum FileTreeSupport {
    /// Returns the path of `item` relative to `root`, or nil when `item` is not inside `root`.
    public static func relativePath(of item: URL, under root: URL) -> String? {
        let itemPath = item.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if itemPath == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard itemPath.hasPrefix(prefix) else { return nil }
        return String(itemPath.dropFirst(prefix.count))
    }

    public static func filesHaveSameContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rightValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard leftValues.fileSize == rightValues.fileSize else { return false }
        return try Data(contentsOf: lhs) == Data(contentsOf: rhs)
    }
}

public enum EnvFile {
    /// Reads `.env` in `root`. Returns an empty dictionary when the file is absent or unreadable.
    public static func read(root: URL) -> [String: String] {
        read(at: root.appendingPathComponent(".env"))
    }

    public static func read(at file: URL) -> [String: String] {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        return parse(source)
    }

    public static func parse(_ source: String) -> [String: String] {
        var output: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("export ") {
                trimmed = String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            output[key] = unquote(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return output
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

public enum BuildFormatting {
    public static func formatDuration(since start: Date) -> String {
        let seconds = Date().timeIntervalSince(start)
        if seconds < 10 {
            return String(format: "%.2fs", seconds)
        }
        return String(format: "%.1fs", seconds)
    }
}
