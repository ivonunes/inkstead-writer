import Foundation
import Plume

extension ThemeRenderer {
    func jsonReady(_ value: Any) -> Any {
        if value is NSNull || value is String || value is Bool || value is Int || value is Double {
            return value
        }
        if let values = value as? [Any] {
            return values.map(jsonReady)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(jsonReady)
        }
        return String(describing: value)
    }

    func meta(
        title: String, canonicalUrl: String, description: String?, feeds: [[String: Any]]? = nil
    ) -> [String: Any] {
        [
            "title": title == config.site.title ? title : "\(title) - \(config.site.title)",
            "canonicalUrl": canonicalUrl,
            "description": description ?? "",
            "feedAlternates": feeds ?? [
                [
                    "type": "application/rss+xml", "title": "\(config.site.title) RSS",
                    "href": "/feed.xml",
                ],
                [
                    "type": "application/feed+json", "title": "\(config.site.title) JSON Feed",
                    "href": "/feed.json",
                ],
            ],
        ]
    }

    func plainText(_ html: String) -> String {
        html.replacingOccurrences(
            of: #"<(br|/p|/div|/li|/h[1-6]|/blockquote)\b[^>]*>"#, with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
