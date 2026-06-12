import Foundation

public enum DevSupport {
    public static let reservedPathPrefix = "/__inkstead-writer"
    public static let changesPath = "/__inkstead-writer/changes"

    public static func isReservedPath(_ urlPathname: String) -> Bool {
        urlPathname == reservedPathPrefix || urlPathname.hasPrefix(reservedPathPrefix + "/")
    }

    public static func queryValue(_ name: String, in querySuffix: String) -> String? {
        let query = querySuffix.hasPrefix("?") ? String(querySuffix.dropFirst()) : querySuffix
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.first.map(String.init) == name else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            return value.removingPercentEncoding ?? value
        }
        return nil
    }

    public static func liveReloadScript(token: String) -> String {
        """
        <script>(() => {
            let token = "\(token)";
            const poll = async () => {
                try {
                    const response = await fetch("\(changesPath)?token=" + encodeURIComponent(token), { cache: "no-store" });
                    if (response.status === 200) {
                        const payload = await response.json();
                        if (payload.token && payload.token !== token) {
                            console.log("Inkstead Writer: content changed, reloading");
                            location.reload();
                            return;
                        }
                    }
                    poll();
                } catch {
                    setTimeout(poll, 1000);
                }
            };
            poll();
        })();</script>
        """
    }

    public static func injectingLiveReload(into body: Data, token: String) -> Data {
        let snippet = Data(liveReloadScript(token: token).utf8)
        let closingTag = body.range(of: Data("</body>".utf8), options: .backwards)
            ?? body.range(of: Data("</BODY>".utf8), options: .backwards)
        guard let closingTag else { return body + snippet }
        var injected = body
        injected.insert(contentsOf: snippet, at: closingTag.lowerBound)
        return injected
    }

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
        let decoded = urlPathname.removingPercentEncoding ?? urlPathname
        let clean = decoded.replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
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
