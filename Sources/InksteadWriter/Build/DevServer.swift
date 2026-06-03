import Foundation

#if os(Windows)
public final class DevServer: @unchecked Sendable {
    public private(set) var port: Int

    public init(root: URL, config: InksteadWriterConfig, port: Int = 4321, rebuildOnRequest: Bool = true) {
        _ = root
        _ = config
        _ = rebuildOnRequest
        self.port = port
    }

    public func start() throws {
        throw InksteadWriterError.io("Inkstead Writer dev server is not available on Windows yet. Use ./inkstead-writer build and serve the output directory with a local static server.")
    }

    public func stop() {}
}
#else
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public final class DevServer: @unchecked Sendable {
    public private(set) var port: Int

    private let root: URL
    private let config: InksteadWriterConfig
    private let rebuildOnRequest: Bool
    private var socketFD: Int32 = -1
    private var thread: Thread?
    private var running = false
    private var inputSignature: String?

    public init(root: URL, config: InksteadWriterConfig, port: Int = 4321, rebuildOnRequest: Bool = true) {
        self.root = root
        self.config = config
        self.port = port
        self.rebuildOnRequest = rebuildOnRequest
    }

    public func start() throws {
        if running { return }
        try SiteBuilder.build(root: root, config: config)
        inputSignature = try? DevInputSnapshot.signature(root: root, config: config)
        #if canImport(Musl)
        let streamSocket = SOCK_STREAM
        #elseif canImport(Glibc)
        let streamSocket = Int32(SOCK_STREAM.rawValue)
        #else
        let streamSocket = SOCK_STREAM
        #endif
        socketFD = socket(AF_INET, streamSocket, 0)
        guard socketFD >= 0 else { throw InksteadWriterError.io("Could not create dev server socket.") }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            closeSocket(socketFD)
            socketFD = -1
            throw InksteadWriterError.io("Could not bind dev server to port \(port).")
        }

        var bound = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(socketFD, $0, &boundLength)
            }
        }
        port = Int(in_port_t(bigEndian: bound.sin_port))

        guard listen(socketFD, 16) == 0 else {
            closeSocket(socketFD)
            socketFD = -1
            throw InksteadWriterError.io("Could not listen on dev server socket.")
        }

        running = true
        thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread?.start()
    }

    public func stop() {
        running = false
        if socketFD >= 0 {
            shutdown(socketFD, Int32(SHUT_RDWR))
            closeSocket(socketFD)
            socketFD = -1
        }
    }

    private func acceptLoop() {
        while running {
            var clientAddress = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(socketFD, &clientAddress, &length)
            if client >= 0 {
                handle(client)
                closeSocket(client)
            }
        }
    }

    private func handle(_ client: Int32) {
        guard let request = readRequest(client) else {
            writeResponse(client, status: 400, contentType: "text/plain; charset=utf-8", body: Data("Bad request".utf8))
            return
        }

        if rebuildOnRequest { rebuildIfNeeded() }
        let dist = root.appendingPathComponent(config.build?.output ?? "dist")
        if request.method == "GET",
           let redirectPath = DevSupport.trailingSlashRedirectPath(for: request.pathOnly) {
            let redirectRelative = DevSupport.staticFilePath(for: redirectPath)
            let redirectFile = dist.appendingPathComponent(redirectRelative).standardizedFileURL
            if redirectFile.path.hasPrefix(dist.standardizedFileURL.path + "/"),
               FileManager.default.fileExists(atPath: redirectFile.path) {
                writeRedirect(client, status: 308, location: redirectPath + request.querySuffix)
                return
            }
        }
        let relative = DevSupport.staticFilePath(for: request.pathOnly)
        let file = dist.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(dist.standardizedFileURL.path + "/"), let body = try? Data(contentsOf: file) else {
            writeResponse(client, status: 404, contentType: "text/plain; charset=utf-8", body: Data("Not found".utf8))
            return
        }
        writeResponse(client, status: 200, contentType: DevSupport.contentType(for: file.path), body: body)
    }

    private func writeRedirect(_ client: Int32, status: Int, location: String) {
        let reason = statusReason(status)
        let body = Data("Redirecting to \(location)\n".utf8)
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Location: \(location)\r\n"
        header += "Content-Type: text/plain; charset=utf-8\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        response.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            _ = send(client, base, response.count, 0)
        }
    }

    private func rebuildIfNeeded() {
        guard let currentSignature = try? DevInputSnapshot.signature(root: root, config: config),
              currentSignature != inputSignature else {
            return
        }
        do {
            try SiteBuilder.build(root: root, config: config, options: .incremental)
            inputSignature = try? DevInputSnapshot.signature(root: root, config: config)
        } catch {
            inputSignature = currentSignature
        }
    }

    private func readRequest(_ client: Int32) -> HTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var expectedLength: Int?

        while true {
            let count = recv(client, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if expectedLength == nil, let headerRange = data.range(of: Data("\r\n\r\n".utf8)) {
                let headers = String(data: data[..<headerRange.lowerBound], encoding: .utf8) ?? ""
                let contentLength = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
                expectedLength = headerRange.upperBound + contentLength
            }
            if let expectedLength, data.count >= expectedLength { break }
        }

        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let body = Data(data[headerRange.upperBound...])
        return HTTPRequest(method: parts[0], path: parts[1], body: body.isEmpty ? nil : body)
    }

    private func writeResponse(_ client: Int32, status: Int, contentType: String, body: Data) {
        let reason = statusReason(status)
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        response.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            _ = send(client, base, response.count, 0)
        }
    }

    private func statusReason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 404: "Not Found"
        default: "OK"
        }
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var body: Data?

    var pathOnly: String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }

    var querySuffix: String {
        guard let index = path.firstIndex(of: "?") else { return "" }
        return String(path[index...])
    }
}

private func closeSocket(_ fd: Int32) {
    #if canImport(Musl)
    _ = Musl.close(fd)
    #elseif canImport(Glibc)
    _ = Glibc.close(fd)
    #elseif canImport(Darwin)
    _ = Darwin.close(fd)
    #endif
}

private enum DevInputSnapshot {
    static func signature(root: URL, config: InksteadWriterConfig) throws -> String {
        var lines: [String] = []
        let candidates = snapshotRoots(root: root, config: config)
        for candidate in candidates {
            try appendSnapshot(candidate, root: root, to: &lines)
        }
        return SHA256.hex(Data(lines.sorted().joined(separator: "\n").utf8))
    }

    private static func snapshotRoots(root: URL, config: InksteadWriterConfig) -> [URL] {
        var roots = [
            root.appendingPathComponent("inkstead-writer.json"),
            root.appendingPathComponent("inkstead.config.ts"),
            root.appendingPathComponent(config.content.posts),
            root.appendingPathComponent(config.content.pages),
            root.appendingPathComponent(config.content.collections),
            root.appendingPathComponent(config.content.media),
            root.appendingPathComponent(config.theme?.path ?? "theme")
        ]
        for asset in config.assets?.passthrough ?? [] {
            roots.append(root.appendingPathComponent(asset.from))
        }
        return roots
    }

    private static func appendSnapshot(_ url: URL, root: URL, to lines: inout [String]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        if values.isRegularFile == true {
            lines.append(line(for: url, root: root, values: values))
            return
        }
        guard values.isDirectory == true,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return
        }
        for case let item as URL in enumerator {
            let itemValues = try item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard itemValues.isRegularFile == true else { continue }
            lines.append(line(for: item, root: root, values: itemValues))
        }
    }

    private static func line(for url: URL, root: URL, values: URLResourceValues) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relative)|\(values.fileSize ?? 0)|\(String(format: "%.6f", modified))"
    }
}
#endif
