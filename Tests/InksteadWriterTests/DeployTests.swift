import XCTest
@testable import InksteadWriter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DeployTests: XCTestCase {
    func testSHA256MatchesKnownDigest() {
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testBLAKE3MatchesKnownDigests() {
        XCTAssertEqual(BLAKE3.hex(Data()), "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
        XCTAssertEqual(BLAKE3.hex(Data("abc".utf8)), "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")
    }

    func testBLAKE3MatchesOfficialChunkBoundaryVectors() {
        let cases: [(Int, String)] = [
            (1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"),
            (1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"),
            (1025, "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444"),
            (2048, "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a")
        ]

        for (length, expected) in cases {
            let input = Data((0..<length).map { UInt8($0 % 251) })
            XCTAssertEqual(BLAKE3.hex(input), expected, "input length \(length)")
        }
    }

    func testCloudflareDeployUsesDirectAssetsApi() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist/assets"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        try "body{}".write(to: root.url.appendingPathComponent("dist/assets/site.css"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var requests: [URLRequest] = []
        var uploadedHTMLHash: String?
        var uploadedCSSHash: String?

        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
            http: { request in
                requests.append(request)
                switch request.url?.path {
                case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-token")
                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    let manifest = try XCTUnwrap(json["manifest"] as? [String: [String: Any]])
                    XCTAssertNotNil(manifest["/index.html"])
                    XCTAssertNotNil(manifest["/assets/site.css"])
                    let htmlHash = try XCTUnwrap(manifest["/index.html"]?["hash"] as? String)
                    let cssHash = try XCTUnwrap(manifest["/assets/site.css"]?["hash"] as? String)
                    let wranglerHTMLHashInput = Data((Data("<h1>Hello</h1>".utf8).base64EncodedString() + "html").utf8)
                    let wranglerCSSHashInput = Data((Data("body{}".utf8).base64EncodedString() + "css").utf8)
                    XCTAssertEqual(htmlHash, String(BLAKE3.hex(wranglerHTMLHashInput).prefix(32)))
                    XCTAssertEqual(cssHash, String(BLAKE3.hex(wranglerCSSHashInput).prefix(32)))
                    uploadedHTMLHash = htmlHash
                    uploadedCSSHash = cssHash
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["\#(htmlHash)","\#(cssHash)"]]}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/assets/upload":
                    XCTAssertEqual(request.url?.query, "base64=true")
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer upload-token")
                    let body = try XCTUnwrap(request.httpBody)
                    XCTAssertNil(body.range(of: Data(#"name="body""#.utf8)))
                    XCTAssertNotNil(body.range(of: Data(#"name="\#(uploadedHTMLHash ?? "")""#.utf8)))
                    XCTAssertNotNil(body.range(of: Data(#"name="\#(uploadedCSSHash ?? "")""#.utf8)))
                    XCTAssertNotNil(body.range(of: Data((uploadedHTMLHash ?? "").utf8)))
                    XCTAssertNotNil(body.range(of: Data((uploadedCSSHash ?? "").utf8)))
                    XCTAssertNotNil(body.range(of: Data("Content-Type: text/html; charset=utf-8".utf8)))
                    XCTAssertNotNil(body.range(of: Data("Content-Type: text/css".utf8)))
                    XCTAssertNotNil(body.range(of: Data("PGgxPkhlbGxvPC9oMT4=".utf8)))
                    XCTAssertNotNil(body.range(of: Data("Ym9keXt9".utf8)))
                    return HTTPResponse(statusCode: 201, body: Data(#"{"success":true,"result":{"jwt":"completion-token"}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/scripts/my-worker":
                    XCTAssertEqual(request.httpMethod, "PUT")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-token")
                    let body = try XCTUnwrap(request.httpBody)
                    XCTAssertNotNil(body.range(of: Data("completion-token".utf8)))
                    XCTAssertNotNil(body.range(of: Data(#""main_module":"main.js""#.utf8)))
                    XCTAssertNotNil(body.range(of: Data("env.ASSETS.fetch(request)".utf8)))
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"id":"my-worker"}}"#.utf8))
                default:
                    XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                    return HTTPResponse(statusCode: 404)
                }
            },
            run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") }
        )

        XCTAssertEqual(requests.count, 3)
    }

    func testCloudflareDeployDeduplicatesIdenticalAssetHashes() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Gone</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        try "<h1>Gone</h1>".write(to: root.url.appendingPathComponent("dist/404.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var requests: [URLRequest] = []
        var sharedHash = ""

        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
            http: { request in
                requests.append(request)
                switch request.url?.path {
                case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    let manifest = try XCTUnwrap(json["manifest"] as? [String: [String: Any]])
                    let indexHash = try XCTUnwrap(manifest["/index.html"]?["hash"] as? String)
                    let notFoundHash = try XCTUnwrap(manifest["/404.html"]?["hash"] as? String)
                    XCTAssertEqual(indexHash, notFoundHash)
                    sharedHash = indexHash
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["\#(indexHash)"]]}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/assets/upload":
                    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                    XCTAssertEqual(body.components(separatedBy: #"name="\#(sharedHash)""#).count - 1, 1)
                    XCTAssertTrue(body.contains("PGgxPkdvbmU8L2gxPg=="))
                    return HTTPResponse(statusCode: 201, body: Data(#"{"success":true,"result":{"jwt":"completion-token"}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/scripts/my-worker":
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"id":"my-worker"}}"#.utf8))
                default:
                    XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                    return HTTPResponse(statusCode: 404)
                }
            },
            run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") }
        )

        XCTAssertEqual(requests.count, 3)
    }

    func testCloudflareAssetUploadRetriesTransientFailure() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var assetUploadAttempts = 0

        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
            http: { request in
                switch request.url?.path {
                case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    let manifest = try XCTUnwrap(json["manifest"] as? [String: [String: Any]])
                    let hash = try XCTUnwrap(manifest["/index.html"]?["hash"] as? String)
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["\#(hash)"]]}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/assets/upload":
                    assetUploadAttempts += 1
                    if assetUploadAttempts == 1 {
                        return HTTPResponse(statusCode: 500, body: Data(#"{"success":false,"errors":[{"message":"temporary"}]}"#.utf8))
                    }
                    return HTTPResponse(statusCode: 201, body: Data(#"{"success":true,"result":{"jwt":"completion-token"}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/scripts/my-worker":
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"id":"my-worker"}}"#.utf8))
                default:
                    XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                    return HTTPResponse(statusCode: 404)
                }
            },
            run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") },
            log: { _ in }
        )

        XCTAssertEqual(assetUploadAttempts, 2)
    }

    func testCloudflareAssetUploadRetriesTransportFailure() async throws {
        struct TransportError: Error {}
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var assetUploadAttempts = 0

        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
            http: { request in
                switch request.url?.path {
                case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                    let body = try XCTUnwrap(request.httpBody)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    let manifest = try XCTUnwrap(json["manifest"] as? [String: [String: Any]])
                    let hash = try XCTUnwrap(manifest["/index.html"]?["hash"] as? String)
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["\#(hash)"]]}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/assets/upload":
                    assetUploadAttempts += 1
                    if assetUploadAttempts == 1 {
                        throw TransportError()
                    }
                    return HTTPResponse(statusCode: 201, body: Data(#"{"success":true,"result":{"jwt":"completion-token"}}"#.utf8))
                case "/client/v4/accounts/account-id/workers/scripts/my-worker":
                    return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"id":"my-worker"}}"#.utf8))
                default:
                    XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                    return HTTPResponse(statusCode: 404)
                }
            },
            run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") },
            log: { _ in }
        )

        XCTAssertEqual(assetUploadAttempts, 2)
    }

    func testCloudflareAssetUploadDoesNotRetryClientError() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var assetUploadAttempts = 0

        do {
            try await Deploy.deploySite(
                root: root.url,
                config: config,
                env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
                http: { request in
                    switch request.url?.path {
                    case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                        let body = try XCTUnwrap(request.httpBody)
                        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                        let manifest = try XCTUnwrap(json["manifest"] as? [String: [String: Any]])
                        let hash = try XCTUnwrap(manifest["/index.html"]?["hash"] as? String)
                        return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["\#(hash)"]]}}"#.utf8))
                    case "/client/v4/accounts/account-id/workers/assets/upload":
                        assetUploadAttempts += 1
                        return HTTPResponse(statusCode: 401, body: Data(#"{"success":false,"errors":[{"message":"invalid token"}]}"#.utf8))
                    default:
                        XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                        return HTTPResponse(statusCode: 404)
                    }
                },
                run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") },
                log: { _ in }
            )
            XCTFail("Expected Cloudflare 401 to throw without retrying.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("invalid token"))
        }

        XCTAssertEqual(assetUploadAttempts, 1)
    }

    func testCloudflareUnknownAssetHashFailsWithoutUploadAttempts() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        var assetUploadAttempts = 0

        do {
            try await Deploy.deploySite(
                root: root.url,
                config: config,
                env: ["CLOUDFLARE_ACCOUNT_ID": "account-id", "CLOUDFLARE_API_TOKEN": "api-token"],
                http: { request in
                    switch request.url?.path {
                    case "/client/v4/accounts/account-id/workers/scripts/my-worker/assets-upload-session":
                        return HTTPResponse(statusCode: 200, body: Data(#"{"success":true,"result":{"jwt":"upload-token","buckets":[["bogus-hash"]]}}"#.utf8))
                    case "/client/v4/accounts/account-id/workers/assets/upload":
                        assetUploadAttempts += 1
                        return HTTPResponse(statusCode: 201, body: Data(#"{"success":true,"result":{"jwt":"completion-token"}}"#.utf8))
                    default:
                        XCTFail("Unexpected Cloudflare request: \(request.url?.absoluteString ?? "nil")")
                        return HTTPResponse(statusCode: 404)
                    }
                },
                run: { _, _ in XCTFail("Cloudflare deploy should use the API, not an external CLI.") },
                log: { _ in }
            )
            XCTFail("Expected unknown asset hash to throw.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("unknown asset hash bogus-hash"))
        }

        XCTAssertEqual(assetUploadAttempts, 0)
    }

    func testDeployReadsDotEnvStrippingQuotesAndExportPrefix() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        try """
        # Netlify credentials
        export NETLIFY_SITE_ID = "site-id"
        NETLIFY_AUTH_TOKEN='token'
        """.write(to: root.url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .netlify)
        )

        var capturedRequest: URLRequest?
        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: [:],
            http: { request in
                capturedRequest = request
                return HTTPResponse(statusCode: 200, body: Data(#"{"state":"ready"}"#.utf8))
            },
            run: { _, _ in XCTFail("Netlify deploy should use the API, not an external CLI.") }
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.netlify.com/api/v1/sites/site-id/deploys")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testNetlifyRequiresEnvAndPostsZipToApi() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist/assets"), withIntermediateDirectories: true)
        try "<h1>Hello</h1>".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        try "body{}".write(to: root.url.appendingPathComponent("dist/assets/site.css"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .netlify)
        )

        do {
            try await Deploy.deploySite(root: root.url, config: config, env: [:])
            XCTFail("Expected missing Netlify credentials to throw.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("NETLIFY_SITE_ID"))
        }

        var capturedRequest: URLRequest?
        try await Deploy.deploySite(
            root: root.url,
            config: config,
            env: ["NETLIFY_SITE_ID": "site-id", "NETLIFY_AUTH_TOKEN": "token"],
            http: { request in
                capturedRequest = request
                return HTTPResponse(statusCode: 200, body: Data(#"{"state":"ready"}"#.utf8))
            },
            run: { _, _ in XCTFail("Netlify deploy should use the API, not an external CLI.") }
        )
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.netlify.com/api/v1/sites/site-id/deploys")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/zip")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: Data("index.html".utf8)))
        XCTAssertNotNil(body.range(of: Data("<h1>Hello</h1>".utf8)))
        XCTAssertNotNil(body.range(of: Data("assets/site.css".utf8)))
    }

    func testNetlifySurfacesApiFailure() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "Nope".write(to: root.url.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .netlify)
        )

        do {
            try await Deploy.deploySite(
                root: root.url,
                config: config,
                env: ["NETLIFY_SITE_ID": "site-id", "NETLIFY_AUTH_TOKEN": "token"],
                http: { _ in HTTPResponse(statusCode: 422) }
            )
            XCTFail("Expected Netlify API failure to throw.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Netlify deploy returned 422"))
        }
    }

    func testPagesDeploysOnlyInsideCi() async throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("dist"), withIntermediateDirectories: true)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .githubPages)
        )

        do {
            try await Deploy.deploySite(root: root.url, config: config, env: [:])
            XCTFail("Expected GitHub Pages deploy outside CI to throw.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("GitHub Actions"))
        }
        try await Deploy.deploySite(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("dist/.nojekyll").path))
    }
}
