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
        }
    }

    public static func requirements(for config: InksteadWriterConfig) -> [AdapterRequirement] {
        var output: [AdapterRequirement] = []
        if config.deploy?.provider == .cloudflareWorkers {
            output.append(AdapterRequirement(environmentVariable: "CLOUDFLARE_API_TOKEN", description: "Cloudflare API token with Workers write access."))
            output.append(AdapterRequirement(environmentVariable: "CLOUDFLARE_ACCOUNT_ID", description: "Cloudflare account ID."))
        }
        if config.deploy?.provider == .netlify {
            output.append(AdapterRequirement(environmentVariable: "NETLIFY_SITE_ID", description: "Netlify site ID."))
            output.append(AdapterRequirement(environmentVariable: "NETLIFY_AUTH_TOKEN", description: "Netlify authentication token."))
        }
        for provider in config.syndication?.providers ?? [] {
            switch provider {
            case .mastodon:
                output.append(AdapterRequirement(environmentVariable: "MASTODON_INSTANCE_URL", description: "Mastodon instance URL."))
                output.append(AdapterRequirement(environmentVariable: "MASTODON_ACCESS_TOKEN", description: "Mastodon access token."))
            case .bluesky:
                output.append(AdapterRequirement(environmentVariable: "BLUESKY_IDENTIFIER", description: "Bluesky account identifier."))
                output.append(AdapterRequirement(environmentVariable: "BLUESKY_APP_PASSWORD", description: "Bluesky app password."))
            case .flickr:
                output.append(AdapterRequirement(environmentVariable: "FLICKR_API_KEY", description: "Flickr API key."))
                output.append(AdapterRequirement(environmentVariable: "FLICKR_API_SECRET", description: "Flickr API secret."))
                output.append(AdapterRequirement(environmentVariable: "FLICKR_ACCESS_TOKEN", description: "Flickr access token."))
                output.append(AdapterRequirement(environmentVariable: "FLICKR_ACCESS_SECRET", description: "Flickr access secret."))
            }
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0.environmentVariable).inserted }
    }

    public static func workflowFile(config: InksteadWriterConfig) -> GeneratedFile? {
        guard let provider = config.ci?.provider else { return nil }
        let envBlock = requirements(for: config).isEmpty ? "" : """

            env:
        \(requirements(for: config).map { "      \($0.environmentVariable): ${{ secrets.\($0.environmentVariable) }}" }.joined(separator: "\n"))
        """
        let githubSetupSteps = githubDependencySetupSteps(config: config)
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
                      - uses: actions/checkout@v6\(githubCacheSteps)\(githubSetupSteps)
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
                  - uses: actions/checkout@v6\(githubCacheSteps)\(githubSetupSteps)
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
                    - .cache/inkstead-writer/media/
                    - .cache/inkstead-writer/data/
                before_script:
                  - apt-get update
                  - apt-get install -y --no-install-recommends ca-certificates curl tar
                pages:
                  script:
                    - ./inkstead-writer publish
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
                - .cache/inkstead-writer/media/
                - .cache/inkstead-writer/data/
            before_script:
              - apt-get update
              - apt-get install -y --no-install-recommends ca-certificates curl tar
            publish:
              script:
                - ./inkstead-writer publish
            """)
        case .forgejoActions:
            return GeneratedFile(path: ".forgejo/workflows/publish.yml", content: """
            name: Publish
            on: [push]
            jobs:
              publish:
                runs-on: docker
                container:
                  image: ubuntu:24.04
                steps:
                  - uses: actions/checkout@v6
                  - uses: actions/cache@v5
                    with:
                      path: |
                        ~/.cache/inkstead-writer/media
                        ~/.cache/inkstead-writer/data
                      key: inkstead-writer-${{ runner.os }}-${{ hashFiles('inkstead-writer.json') }}
                      restore-keys: |
                        inkstead-writer-${{ runner.os }}-
                  - name: Install wrapper dependencies
                    run: |
                      apt-get update
                      apt-get install -y --no-install-recommends ca-certificates curl tar
                  - run: ./inkstead-writer publish
            """)
        }
    }

    private static func githubInksteadCacheSteps() -> String {
        """

              - uses: actions/cache@v5
                with:
                  path: |
                    ~/.cache/inkstead-writer/media
                    ~/.cache/inkstead-writer/data
                  key: inkstead-writer-${{ runner.os }}-${{ hashFiles('inkstead-writer.json') }}
                  restore-keys: |
                    inkstead-writer-${{ runner.os }}-
        """
    }

    private static func githubDependencySetupSteps(config: InksteadWriterConfig) -> String {
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
