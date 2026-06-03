import Foundation

public enum AgentContextRenderer {
    public static let fileName = "AGENTS.md"

    public static func render(root: URL, config: InksteadWriterConfig) -> String {
        let configPath = configFilePath(root: root)
        let themePath = config.theme?.path ?? "theme"
        let outputPath = config.build?.output ?? "dist"
        let dataSources = (config.data ?? [:]).keys.sorted()
        let syndicationProviders = config.syndication?.providers.map(\.rawValue).sorted() ?? []

        var lines: [String] = [
            "# Inkstead Writer Agent Context",
            "",
            "This repository is an Inkstead Writer site. Use this context when editing content, templates, theme assets, or build configuration.",
            "",
            "## Project",
            "- Site title: \(config.site.title)",
            "- Site URL: \(config.site.url)",
            "- Site format version: \(config.recordedVersion)",
            "- Inkstead Writer binary version: \(InksteadWriterMetadata.currentVersion)",
            "- Config: \(configPath)",
            "",
            "## Commands",
            "- Build: `./inkstead-writer build`",
            "- Serve locally: `./inkstead-writer dev`",
            "- Check site setup: `./inkstead-writer doctor`",
            "- Validate theme: `./inkstead-writer theme check`",
            "- Format theme: `./inkstead-writer theme format`",
            "- Apply migrations: `./inkstead-writer migrate`",
            "",
            "Run `./inkstead-writer theme check` after editing Plume templates.",
            "",
            "## Paths",
            "- Theme: `\(themePath)`",
            "- Templates: `\(themePath)/**/*.plume`",
            "- Components: `\(themePath)/components/*.plume`",
            "- Posts: `\(config.content.posts)`",
            "- Pages: `\(config.content.pages)`",
            "- Collections: `\(config.content.collections)`",
            "- Media: `\(config.content.media)`",
            "- Build output: `\(outputPath)`"
        ]

        if let passthrough = config.assets?.passthrough, !passthrough.isEmpty {
            lines.append("- Passthrough assets: \(passthrough.map { "`\($0.from)`" }.joined(separator: ", "))")
        }
        if !dataSources.isEmpty {
            lines.append("- Data sources: \(dataSources.map { "`data.\($0)`" }.joined(separator: ", "))")
        }
        if let connection = config.connection {
            lines.append("- App connection repository: `\(connection.repository ?? "auto-detected")`")
        }
        if let ci = config.ci?.provider.rawValue {
            lines.append("- CI provider: `\(ci)`")
        }
        if let deploy = config.deploy?.provider.rawValue {
            lines.append("- Deploy provider: `\(deploy)`")
        }
        if !syndicationProviders.isEmpty {
            lines.append("- Syndication providers: \(syndicationProviders.map { "`\($0)`" }.joined(separator: ", "))")
        }

        lines += [
            "",
            "## Plume Templates",
            "Plume is Inkstead Writer's template language. It is not Liquid, JSX, Vue, Svelte, or Swift.",
            "",
            "Common syntax:",
            "- Output: `{post.title}`",
            "- Literal output: `{\"Draft\" | downcase}`",
            "- Conditionals: `@if post.title { ... } else if site.title { ... } else { ... }`",
            "- Loops: `@for post in posts { ... }`",
            "- Local variables: `@let isActive = page.urlPath == \"/\"`",
            "- Components: `@PostCard(post, style: \"compact\") { ... }`",
            "- Slots: `@slot`, `@slot(name: \"footer\")`, `@content(footer) { ... }`",
            "- State: `@state open = false`",
            "- Actions: `on:click=\"{open.toggle()}\"`",
            "- Classes: `class:active=\"{isActive}\"`, `class+=\"{post.kind}\"`",
            "- Optional attributes: `hidden?=\"{!open}\"`",
            "- Styles: `@style { ... }`, `@style(file: \"styles/site.css\")`",
            "- Client scripts: `@script { ... }`, `@script(file: \"scripts/site.plume\")`",
            "- Raw JavaScript escape hatch: `@script(language: \"javascript\") { ... }`, `@script(file: \"scripts/site.js\")`",
            "- Feed templates: prefer `theme/pages/feed.xml.plume` and `theme/pages/feed.json.plume`; flat `theme/feed.xml.plume` and `theme/feed.json.plume` also work. Category feeds reuse them with `feed.category`; RSS can opt into browser presentation with `@style`, `@script`, and `feed.presentationScriptSrc`",
            "- Images: `@image(\"images/hero.jpg\", alt: \"Hero\", widths: [480, 960])`",
            "- Assets: `{asset(\"images/avatar.png\")}`",
            "- Navigation: `@navigation(root: \"main\", viewTransitions: true) { ... }`",
            "",
            "Prefer Plume components, `@style`, `@image`, declarative actions, client scripts, and data sources before adding custom JavaScript.",
            "",
            "## Plume Client Scripts",
            "`@script` accepts a small browser scripting language that Inkstead Writer compiles to JavaScript.",
            "",
            "Client script syntax:",
            "- DOM queries: `let menu = page.query(\"#menu\")`, `let cards = page.queryAll(\".card\")`",
            "- Scoped queries: `let button = root.query(\"button\")` inside `@script(scoped: true)`",
            "- Events: `on \".toggle\".click { ... }`, `on page.scroll { ... }`, `on page.ready { ... }`",
            "- Branching: `if page.scrollY > 24 { ... } else { ... }`",
            "- Loops: `for card in cards { ... }`",
            "- Classes: `menu.addClass(\"is-open\")`, `menu.removeClass(\"is-open\")`, `menu.toggleClass(\"is-open\", when: page.scrollY > 24)`",
            "- Attributes and text: `button.setAttribute(\"aria-expanded\", \"true\")`, `menu.setText(\"Open\")`",
            "- Page actions: `page.scrollToTop(smooth: true)`, `page.scrollTo(selector: \"#main\", smooth: true)`",
            "- Escape hatch: use `@script(language: \"javascript\")` for browser APIs that the DSL does not cover.",
            "",
            "## Plume Runtime Actions",
            "- State: `name.toggle()`, `name.set(value)`, `name.increment()`, `name.decrement()`",
            "- Page: `page.scrollToTop(smooth: true)`",
            "- Page: `page.scrollTo(selector: \"#main\", smooth: true)`",
            "- Page: `page.addClass(\"is-active\")`, `page.removeClass(\"is-active\")`, `page.toggleClass(\"is-active\")`",
            "- Geometry: `page.measure(event.target, into: [\"sliderX\", \"sliderWidth\"], round: true)`",
            "- Viewport events: `on:visible`, `on:resize`, `on:scroll`",
            "",
            "## Context Objects",
            "- `site`, `config`, `now`",
            "- `posts`, `pages`, `categories`, `photoPosts`",
            "- `collections.posts`, `collections.pages`, `collections.categories`, `collections.photoPosts`",
            "- Custom collections: `collections.<name>` from `\(config.content.collections)/<name>`",
            "- Build-time JSON data: `data.<name>` from configured data sources",
            "- Page templates receive `page`; post templates receive `post`; index/category templates receive `pagination`.",
            "",
            "## Rules For Agents",
            "- Do not write Liquid syntax like `{% if %}` or `{{ value }}`.",
            "- Do not assume npm, Node, or a package manager is required.",
            "- Keep generated output such as `\(outputPath)` out of source edits unless explicitly asked.",
            "- Run `./inkstead-writer theme check` after template changes.",
            "- Run `./inkstead-writer build` when changing rendering, assets, media, data sources, or content behavior."
        ]

        return lines.joined(separator: "\n") + "\n"
    }

    private static func configFilePath(root: URL) -> String {
        let current = root.appendingPathComponent(InksteadWriterMetadata.configFileName)
        if FileManager.default.fileExists(atPath: current.path) {
            return InksteadWriterMetadata.configFileName
        }
        let legacy = root.appendingPathComponent(InksteadWriterMetadata.legacyConfigFileName)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return InksteadWriterMetadata.legacyConfigFileName
        }
        return InksteadWriterMetadata.configFileName
    }
}
