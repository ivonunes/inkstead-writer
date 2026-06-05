import Foundation

public enum DevSupport {
    public static func contentType(for file: String) -> String {
        if file.hasSuffix(".html") { return "text/html; charset=utf-8" }
        if file.hasSuffix(".js") || file.hasSuffix(".mjs") { return "text/javascript; charset=utf-8" }
        if file.hasSuffix(".css") { return "text/css" }
        if file.hasSuffix(".json") { return "application/json" }
        if file.hasSuffix(".xml") { return "application/xml" }
        if file.hasSuffix(".jpg") || file.hasSuffix(".jpeg") { return "image/jpeg" }
        if file.hasSuffix(".png") { return "image/png" }
        if file.hasSuffix(".webp") { return "image/webp" }
        if file.hasSuffix(".svg") { return "image/svg+xml" }
        if file.hasSuffix(".ico") { return "image/x-icon" }
        if file.hasSuffix(".woff2") { return "font/woff2" }
        if file.hasSuffix(".woff") { return "font/woff" }
        if file.hasSuffix(".ttf") { return "font/ttf" }
        if file.hasSuffix(".txt") { return "text/plain; charset=utf-8" }
        return "application/octet-stream"
    }

    public static func staticFilePath(for urlPathname: String) -> String {
        let clean = urlPathname.replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
        if clean.isEmpty || clean.hasSuffix("/") {
            return "\(clean)index.html"
        }
        if URL(fileURLWithPath: clean).pathExtension.isEmpty {
            return "\(clean)/index.html"
        }
        return clean
    }

    public static func trailingSlashRedirectPath(for urlPathname: String) -> String? {
        guard !urlPathname.isEmpty,
              urlPathname != "/",
              !urlPathname.hasSuffix("/") else {
            return nil
        }
        let lastComponent = urlPathname.split(separator: "/").last.map(String.init) ?? ""
        guard URL(fileURLWithPath: lastComponent).pathExtension.isEmpty else {
            return nil
        }
        return "\(urlPathname)/"
    }

}
