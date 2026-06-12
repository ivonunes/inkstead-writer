import Foundation
import XCTest
@testable import InksteadWriter

final class HTTPMultipartFormTests: XCTestCase {
    func testFieldsAndFilesEncodeAsMultipartBody() {
        var form = HTTPMultipartForm(boundary: "TestBoundary")
        form.addField(name: "plain", value: "value")
        form.addField(name: "hash123", value: "QkFTRTY0", contentType: "text/html")
        form.addFile(name: "file", filename: "site.zip", mimeType: "application/zip", bytes: Data([0x50, 0x4b]))

        var expected = Data("""
        --TestBoundary\r
        Content-Disposition: form-data; name="plain"\r
        \r
        value\r
        --TestBoundary\r
        Content-Disposition: form-data; name="hash123"\r
        Content-Type: text/html\r
        \r
        QkFTRTY0\r
        --TestBoundary\r
        Content-Disposition: form-data; name="file"; filename="site.zip"\r
        Content-Type: application/zip\r
        \r

        """.utf8)
        expected.append(Data([0x50, 0x4b]))
        expected.append(Data("\r\n--TestBoundary--\r\n".utf8))

        XCTAssertEqual(form.body(), expected)
    }

    func testEmptyFormIsJustTerminator() {
        let form = HTTPMultipartForm(boundary: "TestBoundary")
        XCTAssertEqual(form.body(), Data("--TestBoundary--\r\n".utf8))
    }

    func testDefaultBoundaryIsUniqueAndHeaderSafe() {
        let first = HTTPMultipartForm()
        let second = HTTPMultipartForm()
        XCTAssertNotEqual(first.boundary, second.boundary)
        XCTAssertTrue(first.boundary.hasPrefix("InksteadWriterBoundary"))
        XCTAssertTrue(first.boundary.allSatisfy { $0.isLetter || $0.isNumber })
    }
}
