import Foundation
import PackagePlugin

@main
struct InksteadWriterAssetsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "InksteadWriterAssets")
        let packageDirectory = context.package.directoryURL
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedInksteadWriterAssets.swift")

        let assets: [(name: String, path: String)] = [
            ("defaultThemeLayoutPlume", "Sources/InksteadWriter/Templates/DefaultTheme/layout.plume"),
            ("defaultThemeHomePlume", "Sources/InksteadWriter/Templates/DefaultTheme/home.plume"),
            ("defaultThemeCategoryPlume", "Sources/InksteadWriter/Templates/DefaultTheme/category.plume"),
            ("defaultThemePostPlume", "Sources/InksteadWriter/Templates/DefaultTheme/post.plume"),
            ("defaultThemePagePlume", "Sources/InksteadWriter/Templates/DefaultTheme/page.plume"),
            ("defaultThemeFeedXMLPlume", "Sources/InksteadWriter/Templates/DefaultTheme/feed.xml.plume"),
            ("defaultThemeFeedJSONPlume", "Sources/InksteadWriter/Templates/DefaultTheme/feed.json.plume"),
            ("defaultComponentCategoriesPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/Categories.plume"),
            ("defaultComponentPaginationPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/Pagination.plume"),
            ("defaultComponentPostCardPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/PostCard.plume"),
            ("defaultComponentPostListPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/PostList.plume"),
            ("defaultComponentSiteFooterPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/SiteFooter.plume"),
            ("defaultComponentSiteHeaderPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/SiteHeader.plume"),
            ("defaultComponentSiteStylesPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/SiteStyles.plume"),
            ("defaultComponentSyndicationLinksPlume", "Sources/InksteadWriter/Templates/DefaultTheme/components/SyndicationLinks.plume")
        ]

        let inputs = assets.map { packageDirectory.appendingPathComponent($0.path) }
        let arguments = ["--output", output.path] + zip(assets, inputs).map { asset, input in
            "\(asset.name)=\(input.path)"
        }

        return [
            .buildCommand(
                displayName: "Generate Inkstead Writer assets",
                executable: tool.url,
                arguments: arguments,
                inputFiles: inputs,
                outputFiles: [output]
            )
        ]
    }
}
