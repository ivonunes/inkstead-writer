import XCTest
@testable import InksteadWriter

final class DevSupportTests: XCTestCase {
    func testResolvesStaticFilePathsLikeCurrentDevServer() {
        XCTAssertEqual(DevSupport.staticFilePath(for: "/"), "index.html")
        XCTAssertEqual(DevSupport.staticFilePath(for: "/posts/hello"), "posts/hello/index.html")
        XCTAssertEqual(DevSupport.staticFilePath(for: "/posts/hello/"), "posts/hello/index.html")
        XCTAssertEqual(DevSupport.staticFilePath(for: "/assets/app.js"), "assets/app.js")
    }

    func testIdentifiesDirectoryPathsThatNeedTrailingSlashRedirects() {
        XCTAssertEqual(DevSupport.trailingSlashRedirectPath(for: "/posts/hello"), "/posts/hello/")
        XCTAssertNil(DevSupport.trailingSlashRedirectPath(for: "/"))
        XCTAssertNil(DevSupport.trailingSlashRedirectPath(for: "/posts/hello/"))
        XCTAssertNil(DevSupport.trailingSlashRedirectPath(for: "/assets/app.js"))
    }

    func testDecodesPercentEncodedPathsBeforeFileLookup() {
        XCTAssertEqual(DevSupport.staticFilePath(for: "/media/My%20Photo.jpg"), "media/My Photo.jpg")
        XCTAssertEqual(DevSupport.staticFilePath(for: "/posts/caf%C3%A9"), "posts/café/index.html")
        XCTAssertEqual(DevSupport.staticFilePath(for: "/%2e%2e/secret.txt"), "../secret.txt")
    }

    func testServesJavaScriptWithModuleCompatibleMimeType() {
        XCTAssertEqual(DevSupport.contentType(for: "assets/app.js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(DevSupport.contentType(for: "assets/app.mjs"), "text/javascript; charset=utf-8")
        XCTAssertEqual(DevSupport.contentType(for: "index.html"), "text/html; charset=utf-8")
    }

    func testIdentifiesReservedLiveReloadPaths() {
        XCTAssertTrue(DevSupport.isReservedPath("/__inkstead-writer"))
        XCTAssertTrue(DevSupport.isReservedPath("/__inkstead-writer/changes"))
        XCTAssertTrue(DevSupport.isReservedPath("/__inkstead-writer/anything/else"))
        XCTAssertFalse(DevSupport.isReservedPath("/__inkstead-writers"))
        XCTAssertFalse(DevSupport.isReservedPath("/posts/hello/"))
    }

    func testParsesQueryValues() {
        XCTAssertEqual(DevSupport.queryValue("token", in: "?token=abc"), "abc")
        XCTAssertEqual(DevSupport.queryValue("token", in: "?other=1&token=a%20b"), "a b")
        XCTAssertEqual(DevSupport.queryValue("token", in: "?token="), "")
        XCTAssertNil(DevSupport.queryValue("token", in: ""))
        XCTAssertNil(DevSupport.queryValue("token", in: "?other=1"))
    }

    func testInjectsLiveReloadScriptBeforeClosingBodyTag() {
        let html = Data("<html><body><p>Hi</p></body></html>".utf8)
        let injected = DevSupport.injectingLiveReload(into: html, token: "7")
        let text = String(data: injected, encoding: .utf8)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("/__inkstead-writer/changes") == true)
        XCTAssertTrue(text?.contains(#"let token = "7";"#) == true)
        XCTAssertTrue(text?.hasSuffix("</body></html>") == true)
    }

    func testAppendsLiveReloadScriptWhenNoClosingBodyTag() {
        let html = Data("<p>fragment</p>".utf8)
        let injected = DevSupport.injectingLiveReload(into: html, token: "1")
        let text = String(data: injected, encoding: .utf8)
        XCTAssertTrue(text?.hasPrefix("<p>fragment</p>") == true)
        XCTAssertTrue(text?.hasSuffix("</script>") == true)
    }

    func testInjectionPreservesNonUTF8Bytes() {
        var body = Data([0xFF, 0xFE, 0x00, 0x80])
        body.append(Data("</body>".utf8))
        let injected = DevSupport.injectingLiveReload(into: body, token: "2")
        XCTAssertEqual(injected.prefix(4), Data([0xFF, 0xFE, 0x00, 0x80]))
        XCTAssertTrue(injected.count > body.count)
        XCTAssertEqual(injected.suffix(7), Data("</body>".utf8))
    }

}
