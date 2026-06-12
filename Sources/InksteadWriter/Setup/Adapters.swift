import Foundation

public struct AdapterRequirement: Equatable {
    public var environmentVariable: String
    public var description: String
}

public struct DoctorCheck: Equatable {
    public enum Status: String {
        case pass
        case warn
        case fail
    }

    public var status: Status
    public var label: String
    public var message: String?
}

public struct GeneratedFile: Equatable {
    public var path: String
    public var content: String
}

public enum AdapterSupport {
    public static func ciName(_ provider: CiProviderName?) -> String {
        switch provider {
        case .githubActions: "GitHub Actions"
        case .gitlabCi: "GitLab CI"
        case .forgejoActions: "Forgejo Actions"
        case nil: "None"
        }
    }

    public static func deployName(_ provider: DeployProviderName?) -> String {
        switch provider {
        case .cloudflareWorkers: "Cloudflare Workers"
        case .githubPages: "GitHub Pages"
        case .gitlabPages: "GitLab Pages"
        case .netlify: "Netlify"
        case nil: "None"
        }
    }

    public static func syndicationName(_ provider: SyndicationProviderName) -> String {
        switch provider {
        case .mastodon: "Mastodon"
        case .bluesky: "Bluesky"
        case .flickr: "Flickr"
        case .pixelfed: "Pixelfed"
        }
    }

    public static func requirements(for config: InksteadWriterConfig) -> [AdapterRequirement] {
        let syndication = (config.syndication?.providers ?? []).flatMap(syndicationRequirements)
        var seen = Set<String>()
        return (deployRequirements(for: config) + syndication).filter { seen.insert($0.environmentVariable).inserted }
    }

    private static func deployRequirements(for config: InksteadWriterConfig) -> [AdapterRequirement] {
        switch config.deploy?.provider {
        case .cloudflareWorkers:
            return [
                AdapterRequirement(environmentVariable: "CLOUDFLARE_API_TOKEN", description: "Cloudflare API token with Workers write access."),
                AdapterRequirement(environmentVariable: "CLOUDFLARE_ACCOUNT_ID", description: "Cloudflare account ID.")
            ]
        case .netlify:
            return [
                AdapterRequirement(environmentVariable: "NETLIFY_SITE_ID", description: "Netlify site ID."),
                AdapterRequirement(environmentVariable: "NETLIFY_AUTH_TOKEN", description: "Netlify authentication token.")
            ]
        default:
            return []
        }
    }

    private static func syndicationRequirements(_ provider: SyndicationProviderName) -> [AdapterRequirement] {
        switch provider {
        case .mastodon:
            return [
                AdapterRequirement(environmentVariable: "MASTODON_INSTANCE_URL", description: "Mastodon instance URL."),
                AdapterRequirement(environmentVariable: "MASTODON_ACCESS_TOKEN", description: "Mastodon access token.")
            ]
        case .bluesky:
            return [
                AdapterRequirement(environmentVariable: "BLUESKY_IDENTIFIER", description: "Bluesky account identifier."),
                AdapterRequirement(environmentVariable: "BLUESKY_APP_PASSWORD", description: "Bluesky app password.")
            ]
        case .flickr:
            return [
                AdapterRequirement(environmentVariable: "FLICKR_API_KEY", description: "Flickr API key."),
                AdapterRequirement(environmentVariable: "FLICKR_API_SECRET", description: "Flickr API secret."),
                AdapterRequirement(environmentVariable: "FLICKR_ACCESS_TOKEN", description: "Flickr access token."),
                AdapterRequirement(environmentVariable: "FLICKR_ACCESS_SECRET", description: "Flickr access secret.")
            ]
        case .pixelfed:
            return [
                AdapterRequirement(environmentVariable: "PIXELFED_INSTANCE_URL", description: "Pixelfed instance URL."),
                AdapterRequirement(environmentVariable: "PIXELFED_ACCESS_TOKEN", description: "Pixelfed access token.")
            ]
        }
    }

    /// Workflows carry every supported syndication variable, not just the
    /// enabled providers' ones, so enabling a provider later only needs a CI
    /// secret — not a regenerated workflow. Unset secrets resolve to empty
    /// strings in every supported CI provider.
    static func workflowEnvironmentVariables(for config: InksteadWriterConfig) -> [String] {
        let syndication = SyndicationProviderName.allCases.flatMap(syndicationRequirements)
        var seen = Set<String>()
        return (deployRequirements(for: config) + syndication)
            .map(\.environmentVariable)
            .filter { seen.insert($0).inserted }
    }

    public static func workflowFile(config: InksteadWriterConfig) -> GeneratedFile? {
        guard let provider = config.ci?.provider else { return nil }
        let envVariables = workflowEnvironmentVariables(for: config)
        let envBlock = envVariables.isEmpty ? "" : """

            env:
        \(envVariables.map { "      \($0): ${{ secrets.\($0) }}" }.joined(separator: "\n"))
        """
        let setupSteps = dependencySetupSteps(config: config)
        let githubCacheSteps = githubInksteadCacheSteps()
        switch provider {
        case .githubActions:
            if config.deploy?.provider == .githubPages {
                return GeneratedFile(path: ".github/workflows/publish.yml", content: """
                name: Publish
                on:
                  workflow_dispatch:
                  push:
                    branches: [main]
                permissions:
                  contents: write
                  pages: write
                  id-token: write
                jobs:
                  build:
                    runs-on: ubuntu-latest\(envBlock)
                    steps:
                      - uses: actions/checkout@v6\(githubCacheSteps)\(setupSteps)
                      - run: ./inkstead-writer publish
                      - uses: actions/upload-pages-artifact@v4
                        with:
                          path: \(config.build?.output ?? "dist")
                  deploy-pages:
                    needs: build
                    runs-on: ubuntu-latest
                    environment:
                      name: github-pages
                    steps:
                      - uses: actions/deploy-pages@v4
                """)
            }
            return GeneratedFile(path: ".github/workflows/publish.yml", content: """
            name: Publish
            on:
              workflow_dispatch:
              push:
                branches: [main]
            permissions:
              contents: write
            jobs:
              publish:
                runs-on: ubuntu-latest\(envBlock)
                steps:
                  - uses: actions/checkout@v6\(githubCacheSteps)\(setupSteps)
                  - run: ./inkstead-writer publish
            """)
        case .gitlabCi:
            if config.deploy?.provider == .gitlabPages {
                return GeneratedFile(path: ".gitlab-ci.yml", content: """
                image: ubuntu:24.04
                variables:
                  XDG_CACHE_HOME: "$CI_PROJECT_DIR/.cache"
                cache:
                  key: "inkstead-writer-$CI_COMMIT_REF_SLUG"
                  paths:
                    - .cache/inkstead-writer/
                before_script:
                  - apt-get update
                  - apt-get install -y --no-install-recommends ca-certificates curl tar
                pages:
                  script:
                    - ./inkstead-writer publish
                    - ./inkstead-writer cache clean
                  artifacts:
                    paths:
                      - \(config.build?.output ?? "dist")
                  publish: \(config.build?.output ?? "dist")
                """)
            }
            return GeneratedFile(path: ".gitlab-ci.yml", content: """
            image: ubuntu:24.04
            variables:
              XDG_CACHE_HOME: "$CI_PROJECT_DIR/.cache"
            cache:
              key: "inkstead-writer-$CI_COMMIT_REF_SLUG"
              paths:
                - .cache/inkstead-writer/
            before_script:
              - apt-get update
              - apt-get install -y --no-install-recommends ca-certificates curl tar
            publish:
              script:
                - ./inkstead-writer publish
                - ./inkstead-writer cache clean
            """)
        case .forgejoActions:
            return GeneratedFile(path: ".forgejo/workflows/publish.yml", content: """
            name: Publish
            on: [push]
            jobs:
              publish:
                runs-on: docker\(envBlock)
                container:
                  image: ubuntu:24.04
                steps:
                  - uses: actions/checkout@v6
                  - uses: actions/cache@v5
                    with:
                      path: ~/.cache/inkstead-writer
                      key: inkstead-writer-${{ runner.os }}-${{ hashFiles('inkstead-writer.json') }}
                      restore-keys: |
                        inkstead-writer-${{ runner.os }}-
                  - name: Install wrapper dependencies
                    run: |
                      apt-get update
                      apt-get install -y --no-install-recommends ca-certificates curl tar\(setupSteps)
                  - run: ./inkstead-writer publish
                  - run: ./inkstead-writer cache clean
            """)
        }
    }

    private static func githubInksteadCacheSteps() -> String {
        """

              - name: Read Inkstead Writer version
                id: writer_version
                run: |
                  version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' inkstead-writer.json | head -n 1)"
                  if [ -z "$version" ]; then
                    echo "Could not read Inkstead Writer version from inkstead-writer.json." >&2
                    exit 1
                  fi
                  echo "version=$version" >> "$GITHUB_OUTPUT"
              - uses: actions/cache@v5
                with:
                  path: ~/.cache/inkstead-writer/v${{ steps.writer_version.outputs.version }}
                  key: inkstead-writer-bin-${{ runner.os }}-${{ steps.writer_version.outputs.version }}
              - uses: actions/cache@v5
                with:
                  path: |
                    ~/.cache/inkstead-writer/media
                    ~/.cache/inkstead-writer/data
                  key: inkstead-writer-data-${{ runner.os }}-${{ hashFiles('inkstead-writer.json') }}
                  restore-keys: |
                    inkstead-writer-data-${{ runner.os }}-
        """
    }

    private static func dependencySetupSteps(config: InksteadWriterConfig) -> String {
        guard workflowUsesNode(config) else { return "" }
        var steps = "\n      - uses: actions/setup-node@v6\n        with:\n          node-version: lts/*"
        if workflowUsesNPMInstall(config) {
            steps += "\n          cache: npm\n      - run: npm ci"
        }
        return steps
    }

    private static func workflowUsesNode(_ config: InksteadWriterConfig) -> Bool {
        workflowHookCommands(config).contains { command in
            commandHasExecutable(command, names: ["node", "npm", "npx"])
        }
    }

    private static func workflowUsesNPMInstall(_ config: InksteadWriterConfig) -> Bool {
        workflowHookCommands(config).contains { command in
            commandHasExecutable(command, names: ["npm", "npx"])
        }
    }

    private static func workflowHookCommands(_ config: InksteadWriterConfig) -> [String] {
        (config.hooks?.beforeBuild ?? []) + (config.hooks?.afterBuild ?? [])
    }

    private static func commandHasExecutable(_ command: String, names: Set<String>) -> Bool {
        guard let first = command.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first else {
            return false
        }
        return names.contains(String(first))
    }

    public static func adapterChecks(root: URL, config: InksteadWriterConfig, env: [String: String]) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        if config.deploy?.provider == .netlify {
            checks.append(DoctorCheck(status: env["NETLIFY_SITE_ID"].isNilOrEmpty ? .fail : .pass, label: "NETLIFY_SITE_ID is \(env["NETLIFY_SITE_ID"].isNilOrEmpty ? "missing" : "set")"))
            checks.append(DoctorCheck(status: env["NETLIFY_AUTH_TOKEN"].isNilOrEmpty ? .fail : .pass, label: "NETLIFY_AUTH_TOKEN is \(env["NETLIFY_AUTH_TOKEN"].isNilOrEmpty ? "missing" : "set")"))
        }
        if config.deploy?.provider == .cloudflareWorkers {
            checks.append(DoctorCheck(status: config.deploy?.projectName?.isEmpty == false ? .pass : .fail, label: config.deploy?.projectName?.isEmpty == false ? "Cloudflare Worker name configured" : "Cloudflare Worker name missing"))
        }
        return checks
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
