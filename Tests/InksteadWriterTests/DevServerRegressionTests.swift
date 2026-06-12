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

final class DevServerRegressionTests: XCTestCase {
    func testServesPercentEncodedPaths() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let media = root.url.appendingPathComponent("dist/media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try "notes".write(to: media.appendingPathComponent("My Notes.txt"), atomically: true, encoding: .utf8)

        let response = try await fetch("http://127.0.0.1:\(server.port)/media/My%20Notes.txt")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "notes")
    }

    func testBlocksPercentEncodedPathTraversal() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        try "top secret".write(to: root.url.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        for path in ["/../secret.txt", "/%2e%2e/secret.txt", "/%2e%2e%2fsecret.txt"] {
            let response = try sendRawRequest("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n", port: server.port)
            XCTAssertTrue(response.hasPrefix("HTTP/1.1 404"), "Expected 404 for \(path), got: \(response.prefix(40))")
            XCTAssertFalse(response.contains("top secret"), "Traversal leaked file contents for \(path)")
        }
    }

    func testHeadRequestReturnsHeadersWithoutBody() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let response = try sendRawRequest("HEAD / HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n", port: server.port)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK"))
        let separator = "\r\n\r\n"
        let headerEnd = try XCTUnwrap(response.range(of: separator))
        let headers = String(response[..<headerEnd.lowerBound])
        let body = String(response[headerEnd.upperBound...])
        let contentLength = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        XCTAssertGreaterThan(contentLength, 0)
        XCTAssertTrue(body.isEmpty, "HEAD response should not carry a body.")
    }

    func testIdleConnectionDoesNotBlockOtherRequests() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let idle = try openRawSocket(port: server.port)
        defer { closeRegressionSocket(idle) }

        let response = try await fetch("http://127.0.0.1:\(server.port)/")
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(String(data: response.body, encoding: .utf8)?.contains("Hello") == true)
    }

    func testChangesEndpointRespondsImmediatelyToStaleToken() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let response = try sendRawRequest("GET /__inkstead-writer/changes?token=stale HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n", port: server.port)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"), "Expected 200, got: \(response.prefix(40))")
        XCTAssertTrue(response.lowercased().contains("cache-control: no-store"))
        XCTAssertTrue(response.lowercased().contains("content-type: application/json"))
        XCTAssertTrue(response.contains(#""token""#))
    }

    func testChangesEndpointReportsNewTokenAfterContentChange() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: true)
        try server.start()
        defer { server.stop() }

        let initial = try await fetch("http://127.0.0.1:\(server.port)/__inkstead-writer/changes?token=stale")
        XCTAssertEqual(initial.status, 200)
        let initialToken = try XCTUnwrap(decodeToken(initial.body))

        try """
        ---
        title: Hello
        date: 2026-05-10T18:30:00+01:00
        ---

        Body with fresh edits.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-hello.md"), atomically: true, encoding: .utf8)

        let changed = try await fetch("http://127.0.0.1:\(server.port)/__inkstead-writer/changes?token=\(initialToken)")
        XCTAssertEqual(changed.status, 200)
        let changedToken = try XCTUnwrap(decodeToken(changed.body))
        XCTAssertNotEqual(changedToken, initialToken)
    }

    func testReservedNamespaceReturnsNotFoundWithoutShadowingSiteContent() async throws {
        #if os(Windows)
        throw XCTSkip("The local dev server is not implemented on Windows yet.")
        #endif
        let root = try makeSiteRoot()
        let server = DevServer(root: root.url, config: makeConfig(), port: 0, rebuildOnRequest: false)
        try server.start()
        defer { server.stop() }

        let reservedDir = root.url.appendingPathComponent("dist/__inkstead-writer")
        try FileManager.default.createDirectory(at: reservedDir, withIntermediateDirectories: true)
        try "should not be served".write(to: reservedDir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        for path in ["/__inkstead-writer/note.txt", "/__inkstead-writer/other", "/__inkstead-writer"] {
            let response = try sendRawRequest("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n", port: server.port)
            XCTAssertTrue(response.hasPrefix("HTTP/1.1 404"), "Expected 404 for \(path), got: \(response.prefix(40))")
            XCTAssertFalse(response.contains("should not be served"))
        }

        let head = try sendRawRequest("HEAD /__inkstead-writer/changes?token=stale HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n", port: server.port)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200"))
        let headHeaderEnd = try XCTUnwrap(head.range(of: "\r\n\r\n"))
        XCTAssertTrue(String(head[headHeaderEnd.upperBound...]).isEmpty, "HEAD response should not carry a body.")

        let home = try await fetch("http://127.0.0.1:\(server.port)/")
        XCTAssertEqual(home.status, 200)
        XCTAssertTrue(String(data: home.body, encoding: .utf8)?.contains("Hello") == true)
    }

    private func decodeToken(_ body: Data) throws -> String? {
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return payload?["token"] as? String
    }

    private func makeSiteRoot() throws -> TemporaryDirectory {
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
        return root
    }

    private func makeConfig() -> InksteadWriterConfig {
        InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            connection: AppConnectionConfig(provider: .github, repository: "me/site", branch: "main")
        )
    }

    private func fetch(_ url: String) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, data)
    }
}

#if !os(Windows)
private func openRawSocket(port: Int) throws -> Int32 {
    #if canImport(Musl)
    let streamSocket = SOCK_STREAM
    #elseif canImport(Glibc)
    let streamSocket = Int32(SOCK_STREAM.rawValue)
    #else
    let streamSocket = SOCK_STREAM
    #endif
    let socketFD = socket(AF_INET, streamSocket, 0)
    guard socketFD >= 0 else {
        throw NSError(domain: "DevServerRegressionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create raw HTTP socket."])
    }

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
        closeRegressionSocket(socketFD)
        throw NSError(domain: "DevServerRegressionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not connect raw HTTP socket."])
    }
    return socketFD
}

private func sendRawRequest(_ requestText: String, port: Int) throws -> String {
    let socketFD = try openRawSocket(port: port)
    defer { closeRegressionSocket(socketFD) }

    try requestText.utf8CString.withUnsafeBytes { pointer in
        guard let base = pointer.baseAddress else { return }
        var sent = 0
        let count = pointer.count - 1
        while sent < count {
            let written = send(socketFD, base.advanced(by: sent), count - sent, 0)
            guard written > 0 else {
                throw NSError(domain: "DevServerRegressionTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not write raw HTTP request."])
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

private func closeRegressionSocket(_ fd: Int32) {
    #if canImport(Musl)
    _ = Musl.close(fd)
    #elseif canImport(Glibc)
    _ = Glibc.close(fd)
    #elseif canImport(Darwin)
    _ = Darwin.close(fd)
    #endif
}
#endif
