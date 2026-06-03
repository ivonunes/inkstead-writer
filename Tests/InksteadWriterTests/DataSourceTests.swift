import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import InksteadWriter

final class DataSourceTests: XCTestCase {
    func testLoadsLocalJSONDataSources() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("data"), withIntermediateDirectories: true)
        try #"[{"title":"A useful link"}]"#.write(
            to: root.url.appendingPathComponent("data/links.json"),
            atomically: true,
            encoding: .utf8
        )
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            data: [
                "links": DataSourceConfig(file: "data/links.json", required: true)
            ]
        )

        let data = try DataSourceLoader.load(root: root.url, config: config)

        let links = try XCTUnwrap(data["links"] as? [[String: Any]])
        XCTAssertEqual(links.first?["title"] as? String, "A useful link")
    }

    func testLoadsRemoteJSONDataSources() async throws {
        let root = try TemporaryDirectory()
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            data: [
                "repos": DataSourceConfig(
                    url: "https://api.example.com/repos",
                    required: true,
                    headers: ["Authorization": "Bearer token"]
                )
            ]
        )

        let data = try await DataSourceLoader.loadAsync(root: root.url, config: config) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/repos")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return HTTPResponse(statusCode: 200, body: Data(#"[{"name":"Inkstead"}]"#.utf8))
        }

        let repos = try XCTUnwrap(data["repos"] as? [[String: Any]])
        XCTAssertEqual(repos.first?["name"] as? String, "Inkstead")
    }

    func testRemoteDataSourcesUseConditionalRequestsForStaleCache() async throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            data: [
                "repos": DataSourceConfig(url: "https://api.example.com/repos", cache: "0s", required: true)
            ]
        )
        let requests = DataSourceRequestLog()

        _ = try await DataSourceLoader.loadAsync(root: root.url, config: config, cacheRoot: cache) { request in
            requests.count += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return HTTPResponse(
                statusCode: 200,
                body: Data(#"[{"name":"Inkstead"}]"#.utf8),
                headers: ["ETag": #""abc123""#, "Last-Modified": "Wed, 27 May 2026 12:00:00 GMT"]
            )
        }

        let data = try await DataSourceLoader.loadAsync(root: root.url, config: config, cacheRoot: cache) { request in
            requests.count += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), #""abc123""#)
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "Wed, 27 May 2026 12:00:00 GMT")
            return HTTPResponse(statusCode: 304)
        }

        XCTAssertEqual(requests.count, 2)
        let repos = try XCTUnwrap(data["repos"] as? [[String: Any]])
        XCTAssertEqual(repos.first?["name"] as? String, "Inkstead")
    }

    func testOptionalDataSourceReturnsNullOnFailure() async throws {
        let root = try TemporaryDirectory()
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            data: [
                "repos": DataSourceConfig(url: "https://api.example.com/repos", required: false)
            ]
        )

        let data = try await DataSourceLoader.loadAsync(root: root.url, config: config) { _ in
            HTTPResponse(statusCode: 500, body: Data())
        }

        XCTAssertTrue(data["repos"] is NSNull)
    }

    func testRequiredDataSourceFailureIsReported() async throws {
        let root = try TemporaryDirectory()
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            data: [
                "repos": DataSourceConfig(url: "https://api.example.com/repos", required: true)
            ]
        )

        await XCTAssertThrowsErrorAsync(try await DataSourceLoader.loadAsync(root: root.url, config: config) { _ in
            HTTPResponse(statusCode: 503, body: Data())
        }) { error in
            XCTAssertTrue(String(describing: error).contains("HTTP 503"))
        }
    }
}

private final class DataSourceRequestLog: @unchecked Sendable {
    var count = 0
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
