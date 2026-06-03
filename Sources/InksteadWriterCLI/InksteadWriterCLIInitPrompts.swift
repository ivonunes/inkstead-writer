import Foundation
import InksteadWriter

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

extension InksteadWriterCLI {
    enum TerminalStyle {
        static var enabled: Bool {
            isInteractiveTerminal && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        }

        static func accent(_ text: String) -> String { wrap(text, "36") }
        static func bold(_ text: String) -> String { wrap(text, "1") }
        static func dim(_ text: String) -> String { wrap(text, "2") }
        static func green(_ text: String) -> String { wrap(text, "32") }
        static func magenta(_ text: String) -> String { wrap(text, "35") }
        static func red(_ text: String) -> String { wrap(text, "31") }
        static func yellow(_ text: String) -> String { wrap(text, "33") }

        private static func wrap(_ text: String, _ code: String) -> String {
            enabled ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
        }
    }

    enum TerminalKey {
        case up
        case down
        case left
        case right
        case enter
        case space
        case digit(Int)
        case other(UInt8)
    }

    static func shouldPromptInit(_ arguments: [String]) -> Bool {
        guard isInteractiveTerminal else { return false }
        return !arguments.contains { $0.hasPrefix("--") || $0.hasPrefix("-") }
    }

    static var isInteractiveTerminal: Bool {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        #else
            false
        #endif
    }

    static func promptInit(arguments: [String]) throws -> ParsedInitCommand {
        let directory = arguments.first ?? "my-site"
        let siteName = suggestedSiteName(for: directory)
        print(TerminalStyle.bold(TerminalStyle.accent("Inkstead Writer init")))
        print(TerminalStyle.dim("Set up the site, publishing workflow, syndication, and app connection."))
        print()
        let deploy = try promptChoice(
            "Deployment adapter",
            choices: [
                ("cloudflare-workers", "Cloudflare Workers"),
                ("netlify", "Netlify"),
                ("github-pages", "GitHub Pages"),
                ("gitlab-pages", "GitLab Pages"),
                ("none", "None for now"),
            ],
            defaultIndex: 0
        )
        var ci: CiProviderName? = .githubActions
        var deployProvider: DeployProviderName?
        var deployProjectName: String?
        if deploy == "none" {
            deployProvider = nil
        } else {
            deployProvider = DeployProviderName(rawValue: deploy)
        }
        if deployProvider == .cloudflareWorkers {
            deployProjectName = promptLine(
                "Cloudflare Worker name", defaultValue: siteName)
        }
        if deployProvider == .githubPages {
            ci = .githubActions
            print(TerminalStyle.dim("GitHub Pages uses GitHub Actions."))
        } else if deployProvider == .gitlabPages {
            ci = .gitlabCi
            print(TerminalStyle.dim("GitLab Pages uses GitLab CI."))
        } else {
            let selectedCI = try promptChoice(
                "CI adapter",
                choices: [
                    ("github-actions", "GitHub Actions"),
                    ("gitlab-ci", "GitLab CI"),
                    ("forgejo-actions", "Forgejo Actions"),
                    ("none", "None for now"),
                ],
                defaultIndex: 0
            )
            ci = selectedCI == "none" ? nil : CiProviderName(rawValue: selectedCI)
        }
        let syndication = try promptSyndication()
        let connection = try promptConnection(directory: directory, ci: ci)
        return ParsedInitCommand(
            directory: directory,
            options: InitSiteOptions(
                ci: ci, deploy: deployProvider, deployProjectName: deployProjectName,
                syndication: syndication, connection: connection)
        )
    }

    static func promptSyndication() throws -> [SyndicationProviderName] {
        let choices: [(value: String, label: String)] = [
            ("mastodon", "Mastodon"),
            ("bluesky", "Bluesky"),
            ("flickr", "Flickr"),
        ]
        if isInteractiveTerminal {
            return try promptMultiChoice("Syndication adapters", choices: choices)
                .compactMap(SyndicationProviderName.init(rawValue:))
                .sorted { $0.rawValue < $1.rawValue }
        }

        print(TerminalStyle.bold("Syndication adapters"))
        for (index, choice) in choices.enumerated() {
            print("  \(index + 1). \(choice.label)")
        }
        let answer = promptLine("Choose zero or more, comma-separated", defaultValue: "")
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var selected: [SyndicationProviderName] = []
        let numberedChoices = ["1": "mastodon", "2": "bluesky", "3": "flickr"]
        for raw in answer.split(separator: ",").map({
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }) where !raw.isEmpty {
            let value = numberedChoices[raw] ?? raw
            guard let provider = SyndicationProviderName(rawValue: value) else {
                throw InksteadWriterError.config("Unknown syndication provider \(raw).")
            }
            if !selected.contains(provider) { selected.append(provider) }
        }
        return selected.sorted { $0.rawValue < $1.rawValue }
    }

    static func promptConnection(directory: String, ci: CiProviderName?) throws
        -> AppConnectionConfig?
    {
        let siteName = suggestedSiteName(for: directory)
        guard promptYesNo("Configure the Inkstead app connection now?", defaultValue: false) else {
            return nil
        }
        let inferred = inferredConnectionProvider(ci: ci)
        let provider: AppConnectionProviderName
        if let inferred {
            provider = inferred
            print(TerminalStyle.dim("The app connection will use \(providerLabel(inferred)) based on your CI choice."))
        } else {
            let selected = try promptChoice(
                "Connection provider",
                choices: [
                    ("github", "GitHub"),
                    ("gitlab", "GitLab"),
                    ("forgejo", "Forgejo"),
                ],
                defaultIndex: 0
            )
            provider = AppConnectionProviderName(rawValue: selected) ?? .github
        }
        let instanceURL =
            provider == .forgejo
            ? promptLine("Forgejo instance URL", defaultValue: "https://codeberg.org") : nil
        var repository = promptLine(
            "\(providerLabel(provider)) repository",
            defaultValue: "owner/\(siteName)")
        while repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !repository.contains("/")
        {
            repository = promptLine(
                "\(providerLabel(provider)) repository",
                defaultValue: "owner/\(siteName)")
        }
        let branch = promptLine("Branch", defaultValue: "main")
        return AppConnectionConfig(
            provider: provider, repository: repository, branch: branch, instanceUrl: instanceURL)
    }

    static func inferredConnectionProvider(ci: CiProviderName?) -> AppConnectionProviderName? {
        switch ci {
        case .githubActions: .github
        case .gitlabCi: .gitlab
        case .forgejoActions: .forgejo
        case nil: nil
        }
    }

    static func providerLabel(_ provider: AppConnectionProviderName) -> String {
        switch provider {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .forgejo: "Forgejo"
        }
    }

    static func suggestedSiteName(for directory: String) -> String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != ".", !trimmed.isEmpty else { return "my-website" }
        let url = URL(fileURLWithPath: trimmed)
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "my-website" : name
    }

    static func printInitSuccess(directory: String, options: InitSiteOptions, fallback: String) {
        guard isInteractiveTerminal else {
            print(fallback)
            return
        }

        let needsEnvironment = options.deploy != nil || !options.syndication.isEmpty
        let project = directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "my-site" : directory

        print("\(TerminalStyle.green("Created")) \(TerminalStyle.bold("Inkstead Writer site"))")
        print(TerminalStyle.dim("Ready in \(project)"))
        print()
        print(TerminalStyle.bold("Next"))
        printStep(1, "Open the site", command: "cd \(project)")
        if needsEnvironment {
            printStep(2, "Create local secrets", command: "cp .env.example .env")
            print("     \(TerminalStyle.dim("Fill in .env, then mirror those values in CI secrets or variables."))")
            printStep(3, "Check setup", command: "./inkstead-writer doctor")
            printStep(4, "Preview locally", command: "./inkstead-writer dev")
        } else {
            printStep(2, "Check setup", command: "./inkstead-writer doctor")
            printStep(3, "Preview locally", command: "./inkstead-writer dev")
        }
    }

    static func printStep(_ number: Int, _ label: String, command: String) {
        print("  \(TerminalStyle.yellow("\(number).")) \(TerminalStyle.bold(label))")
        print("     \(TerminalStyle.accent(command))")
    }

    static func newPostOptions(arguments: [String]) throws -> CreatePostOptions {
        let kindText = value(after: "--kind", in: arguments) ?? value(after: "-k", in: arguments)
        let title = value(after: "--title", in: arguments) ?? value(after: "-t", in: arguments)
        let text = value(after: "--text", in: arguments)
        if let kindText {
            guard let kind = NewPostKind(rawValue: kindText) else {
                throw InksteadWriterError.config("Post kind must be article or note.")
            }
            if kind == .article, title == nil, isInteractiveTerminal {
                return CreatePostOptions(kind: kind, title: promptLine("Title", defaultValue: nil))
            }
            if kind == .note, text == nil, isInteractiveTerminal {
                return CreatePostOptions(
                    kind: kind, text: promptLine("Note text", defaultValue: nil))
            }
            return CreatePostOptions(kind: kind, title: title, text: text)
        }
        guard isInteractiveTerminal else {
            return CreatePostOptions(kind: .article, title: title, text: text)
        }
        let selected = try promptChoice(
            "Post type",
            choices: [("article", "Long article"), ("note", "Note")],
            defaultIndex: 0
        )
        let kind = NewPostKind(rawValue: selected) ?? .article
        if kind == .article {
            return CreatePostOptions(kind: kind, title: promptLine("Title", defaultValue: nil))
        }
        return CreatePostOptions(kind: kind, text: promptLine("Note text", defaultValue: nil))
    }

    static func promptChoice(
        _ question: String, choices: [(value: String, label: String)], defaultIndex: Int
    ) throws -> String {
        if isInteractiveTerminal {
            return try promptInteractiveChoice(question, choices: choices, defaultIndex: defaultIndex)
        }

        print(TerminalStyle.bold(question))
        for (index, choice) in choices.enumerated() {
            print("  \(index + 1). \(choice.label)")
        }
        let fallback = String(defaultIndex + 1)
        let answer = promptLine("Choice", defaultValue: fallback)
        let index =
            Int(answer).map { $0 - 1 } ?? choices.firstIndex {
                $0.value == answer.lowercased() || $0.label.lowercased() == answer.lowercased()
            } ?? defaultIndex
        guard choices.indices.contains(index) else {
            throw InksteadWriterError.config("Invalid choice \(answer).")
        }
        return choices[index].value
    }

    static func promptYesNo(_ question: String, defaultValue: Bool) -> Bool {
        let fallback = defaultValue ? "Y/n" : "y/N"
        let answer = promptLine(question, defaultValue: fallback).lowercased()
        if answer == fallback.lowercased() || answer.isEmpty { return defaultValue }
        return answer == "y" || answer == "yes"
    }

    static func promptLine(_ question: String, defaultValue: String?) -> String {
        if let defaultValue, !defaultValue.isEmpty {
            print("\(TerminalStyle.bold(question)) \(TerminalStyle.dim("[\(defaultValue)]")): ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return answer.isEmpty ? defaultValue : answer
        }
        print("\(TerminalStyle.bold(question)): ", terminator: "")
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func promptInteractiveChoice(
        _ question: String, choices: [(value: String, label: String)], defaultIndex: Int
    ) throws -> String {
        var selected = choices.indices.contains(defaultIndex) ? defaultIndex : 0
        var renderedLines = 0

        return withRawTerminal {
            while true {
                renderChoice(question, choices: choices, selected: selected, renderedLines: renderedLines)
                renderedLines = choices.count + 2

                switch readTerminalKey() {
                case .up, .left:
                    selected = selected == 0 ? choices.count - 1 : selected - 1
                case .down, .right:
                    selected = selected == choices.count - 1 ? 0 : selected + 1
                case .digit(let number):
                    let index = number - 1
                    if choices.indices.contains(index) {
                        selected = index
                        renderChoice(question, choices: choices, selected: selected, renderedLines: renderedLines)
                        print()
                        return choices[selected].value
                    }
                case .enter, .space:
                    print()
                    return choices[selected].value
                case .other:
                    continue
                }
            }
        }
    }

    static func promptMultiChoice(
        _ question: String, choices: [(value: String, label: String)]
    ) throws -> [String] {
        var selected = 0
        var enabled = Set<Int>()
        var renderedLines = 0

        return withRawTerminal {
            while true {
                renderMultiChoice(
                    question, choices: choices, selected: selected, enabled: enabled,
                    renderedLines: renderedLines)
                renderedLines = choices.count + 2

                switch readTerminalKey() {
                case .up, .left:
                    selected = selected == 0 ? choices.count - 1 : selected - 1
                case .down, .right:
                    selected = selected == choices.count - 1 ? 0 : selected + 1
                case .space:
                    if enabled.contains(selected) {
                        enabled.remove(selected)
                    } else {
                        enabled.insert(selected)
                    }
                case .digit(let number):
                    let index = number - 1
                    if choices.indices.contains(index) {
                        if enabled.contains(index) {
                            enabled.remove(index)
                        } else {
                            enabled.insert(index)
                        }
                        selected = index
                    }
                case .enter:
                    print()
                    return choices.indices.filter { enabled.contains($0) }.map { choices[$0].value }
                case .other:
                    continue
                }
            }
        }
    }

    static func renderChoice(
        _ question: String,
        choices: [(value: String, label: String)],
        selected: Int,
        renderedLines: Int
    ) {
        rewind(lines: renderedLines)
        print(TerminalStyle.bold(question))
        print(TerminalStyle.dim("Use up/down, number keys, or Enter."))
        for (index, choice) in choices.enumerated() {
            let prefix = index == selected ? ">" : " "
            let number = "\(index + 1)."
            let line = "\(prefix) \(number) \(choice.label)"
            print(index == selected ? TerminalStyle.accent(TerminalStyle.bold(line)) : "  \(number) \(choice.label)")
        }
    }

    static func renderMultiChoice(
        _ question: String,
        choices: [(value: String, label: String)],
        selected: Int,
        enabled: Set<Int>,
        renderedLines: Int
    ) {
        rewind(lines: renderedLines)
        print(TerminalStyle.bold(question))
        print(TerminalStyle.dim("Use up/down, Space to toggle, number keys, or Enter."))
        for (index, choice) in choices.enumerated() {
            let cursor = index == selected ? ">" : " "
            let mark = enabled.contains(index) ? "[x]" : "[ ]"
            let number = "\(index + 1)."
            let line = "\(cursor) \(mark) \(number) \(choice.label)"
            let styled = enabled.contains(index) ? TerminalStyle.green(line) : line
            print(index == selected ? TerminalStyle.accent(TerminalStyle.bold(styled)) : "  \(mark) \(number) \(choice.label)")
        }
    }

    static func rewind(lines: Int) {
        guard lines > 0 else { return }
        for _ in 0..<lines {
            print("\u{001B}[1A\u{001B}[2K", terminator: "")
        }
    }

    static func withRawTerminal<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            var original = termios()
            guard tcgetattr(STDIN_FILENO, &original) == 0 else {
                return try body()
            }
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
            raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw)
            defer {
                var restore = original
                _ = tcsetattr(STDIN_FILENO, TCSANOW, &restore)
            }
            return try body()
        #else
            return try body()
        #endif
    }

    static func readTerminalKey() -> TerminalKey {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            var byte: UInt8 = 0
            guard read(STDIN_FILENO, &byte, 1) == 1 else { return .enter }
            if byte == 10 || byte == 13 { return .enter }
            if byte == 32 { return .space }
            if byte >= 49 && byte <= 57 { return .digit(Int(byte - 48)) }
            if byte == 27 {
                var second: UInt8 = 0
                var third: UInt8 = 0
                guard read(STDIN_FILENO, &second, 1) == 1 else { return .other(byte) }
                guard read(STDIN_FILENO, &third, 1) == 1 else { return .other(byte) }
                if second == 91 {
                    switch third {
                    case 65: return .up
                    case 66: return .down
                    case 67: return .right
                    case 68: return .left
                    default: return .other(third)
                    }
                }
                return .other(third)
            }
            return .other(byte)
        #else
            return .enter
        #endif
    }
}
