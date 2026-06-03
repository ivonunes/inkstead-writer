import XCTest
@testable import InksteadWriter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
#endif

final class DevServerTests: XCTestCase {
    func testServesStaticFilesOverHTTP() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try """
        ---
        title: Hello
        date: 2026-05-10T18:30:00+01:00
        ---

        Body.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-hello.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            connection: AppConnectionConfig(provider: .github, repository: "me/site", branch: "main")
        )
        let server = DevServer(root: root.url, config: config, port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let home = try await fetch("http://127.0.0.1:\(server.port)/")
        XCTAssertEqual(home.status, 200)
        XCTAssertTrue(String(data: home.body, encoding: .utf8)?.contains("Hello") == true)
        XCTAssertEqual(home.contentType, "text/html; charset=utf-8")

        let publicConfig = try await fetch("http://127.0.0.1:\(server.port)/inkstead-writer.json")
        XCTAssertEqual(publicConfig.status, 200)
        XCTAssertEqual(publicConfig.contentType, "application/json")
        XCTAssertTrue(String(data: publicConfig.body, encoding: .utf8)?.contains(#""repo" : "site""#) == true)
    }

    func testRedirectsDirectoryPathsToTrailingSlash() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try """
        ---
        title: Hello
        date: 2026-05-10T18:30:00+01:00
        ---

        Body.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-hello.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            connection: AppConnectionConfig(provider: .github, repository: "me/site", branch: "main")
        )
        let server = DevServer(root: root.url, config: config, port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let response = try await sendWithoutFollowingRedirects(URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/2026/05/10/hello")!))

        XCTAssertEqual(response.status, 308)
        XCTAssertEqual(response.location, "/2026/05/10/hello/")
    }

    private func fetch(_ url: String) async throws -> (status: Int, contentType: String?, body: Data) {
        try await send(URLRequest(url: URL(string: url)!))
    }

    private func send(_ request: URLRequest) async throws -> (status: Int, contentType: String?, body: Data) {
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), data)
    }

    private func sendWithoutFollowingRedirects(_ request: URLRequest) async throws -> (status: Int, location: String?, body: Data) {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #else
        let response = try sendRawGET(request)
        let separator = "\r\n\r\n"
        let headerEnd = response.range(of: separator)
        let headers = headerEnd.map { String(response[..<$0.lowerBound]) } ?? response
        let body = headerEnd.map { Data(response[$0.upperBound...].utf8) } ?? Data()
        let lines = headers.components(separatedBy: "\r\n")
        let status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        let location = lines.first { $0.lowercased().hasPrefix("location:") }
            .flatMap { $0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) }
        return (status, location, body)
        #endif
    }
}

#if !os(Windows)
private func sendRawGET(_ request: URLRequest) throws -> String {
    guard let url = request.url,
          let port = url.port else {
        throw NSError(domain: "DevServerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Raw HTTP request requires a local URL with a port."])
    }

    #if canImport(Musl)
    let streamSocket = SOCK_STREAM
    #elseif canImport(Glibc)
    let streamSocket = Int32(SOCK_STREAM.rawValue)
    #else
    let streamSocket = SOCK_STREAM
    #endif
    let socketFD = socket(AF_INET, streamSocket, 0)
    guard socketFD >= 0 else {
        throw NSError(domain: "DevServerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create raw HTTP socket."])
    }
    defer { closeRawSocket(socketFD) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else {
        throw NSError(domain: "DevServerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not connect raw HTTP socket."])
    }

    let path = url.path.isEmpty ? "/" : url.path
    let rawRequest = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
    try rawRequest.utf8CString.withUnsafeBytes { pointer in
        guard let base = pointer.baseAddress else { return }
        var sent = 0
        let count = pointer.count - 1
        while sent < count {
            let written = send(socketFD, base.advanced(by: sent), count - sent, 0)
            guard written > 0 else {
                throw NSError(domain: "DevServerTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not write raw HTTP request."])
            }
            sent += written
        }
    }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = recv(socketFD, &buffer, buffer.count, 0)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

private func closeRawSocket(_ fd: Int32) {
    #if canImport(Musl)
    _ = Musl.close(fd)
    #elseif canImport(Glibc)
    _ = Glibc.close(fd)
    #elseif canImport(Darwin)
    _ = Darwin.close(fd)
    #endif
}
#endif
