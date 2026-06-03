import Foundation

public enum AppConnectionBuild {
    public static func writePublicConfig(to dist: URL, config: InksteadWriterConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(AppConnectionSupport.publicConfig(config))
        try writeIfChanged(
            Data((String(data: configData, encoding: .utf8)! + "\n").utf8),
            to: dist.appendingPathComponent(AppConnectionSupport.publicConfigPath),
        )
    }

    private static func writeIfChanged(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           (try? Data(contentsOf: url)) == data {
            return
        }
        try data.write(to: url)
    }
}
