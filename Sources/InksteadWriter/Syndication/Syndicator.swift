import Foundation

public struct SyndicationSummary: Equatable, Sendable {
    public var changed: Bool
    public var published: Int
    public var failed: Int
}

public enum Syndicator {
    public static func syndicateSite(
        root: URL,
        config: InksteadWriterConfig,
        env: [String: String] = ProcessInfo.processInfo.environment,
        http: @escaping HTTPClient = DefaultHTTPClient.send
    ) async -> SyndicationSummary {
        let posts: [NormalizedPost]
        do {
            posts = try ContentLoader.loadPosts(root: root, config: config)
        } catch {
            return SyndicationSummary(changed: false, published: 0, failed: 1)
        }

        let mergedEnv = readEnv(root: root).merging(env) { _, new in new }
        let context = SyndicationContext(root: root, env: mergedEnv, http: http)
        var changed = false
        var published = 0
        var failed = 0

        for post in posts {
            for provider in post.syndicate {
                if post.syndication[provider.rawValue]?.object?["status"]?.string == "published" { continue }
                if !SyndicationProviders.canSyndicate(provider, post: post) { continue }
                let result = await SyndicationProviders.publish(provider, post: post, context: context)
                do {
                    let raw = try String(contentsOf: post.path, encoding: .utf8)
                    let updated = SyndicationFrontmatter.update(markdown: raw, provider: provider, result: result)
                    try updated.write(to: post.path, atomically: true, encoding: .utf8)
                    changed = true
                } catch {
                    failed += 1
                    continue
                }
                if result.status == .published { published += 1 }
                if result.status == .failed { failed += 1 }
            }
        }
        return SyndicationSummary(changed: changed, published: published, failed: failed)
    }

    private static func readEnv(root: URL) -> [String: String] {
        let file = root.appendingPathComponent(".env")
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var output: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { output[parts[0]] = parts[1] }
        }
        return output
    }
}
