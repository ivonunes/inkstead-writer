enum DefaultTemplates {
    static let names = GeneratedInksteadWriterAssets.defaultTemplateNames

    static func fileName(for name: String) -> String {
        "\(name).plume"
    }

    static func organizedFileName(for name: String) -> String {
        if name == "layout" {
            return "layouts/default.plume"
        }
        return "pages/\(name).plume"
    }

    static let templates = GeneratedInksteadWriterAssets.defaultTemplates
    static let components = GeneratedInksteadWriterAssets.defaultTemplateComponents
}
