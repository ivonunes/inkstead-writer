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

    func testServesJavaScriptWithModuleCompatibleMimeType() {
        XCTAssertEqual(DevSupport.contentType(for: "assets/app.js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(DevSupport.contentType(for: "assets/app.mjs"), "text/javascript; charset=utf-8")
        XCTAssertEqual(DevSupport.contentType(for: "index.html"), "text/html; charset=utf-8")
    }

}
