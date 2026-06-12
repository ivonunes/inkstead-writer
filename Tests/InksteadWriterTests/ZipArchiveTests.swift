import Foundation
import XCTest
@testable import InksteadWriter

final class ZipArchiveTests: XCTestCase {
    private struct LocalFileHeader {
        var flags: UInt16
        var compressionMethod: UInt16
        var crc32: UInt32
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var name: String
        var bytes: Data
    }

    private func makeSiteTree() throws -> (root: TemporaryDirectory, files: [String: Data]) {
        let root = try TemporaryDirectory()
        let files: [String: Data] = [
            "index.html": Data("<h1>Hello</h1>".utf8),
            "assets/app.js": Data("console.log(\"hi\");\n".utf8),
            "assets/img/empty.bin": Data(),
            "média/fotografía—1.txt": Data("non-ascii filename contents".utf8)
        ]
        for (path, bytes) in files {
            let url = root.url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        return (root, files)
    }

    func testLocalFileHeadersRecordCRCSizesAndUTF8Flag() throws {
        let (root, files) = try makeSiteTree()
        let archive = try ZipArchive.archiveDirectory(root.url)

        let headers = try parseLocalFileHeaders(archive)
        XCTAssertEqual(headers.count, files.count)
        XCTAssertEqual(headers.map(\.name).sorted(), files.keys.sorted())

        for header in headers {
            let expected = try XCTUnwrap(files[header.name], "unexpected entry \(header.name)")
            XCTAssertEqual(header.compressionMethod, 0, "\(header.name) should be stored uncompressed")
            XCTAssertEqual(header.bytes, expected, "\(header.name) bytes should round-trip")
            XCTAssertEqual(header.compressedSize, UInt32(expected.count))
            XCTAssertEqual(header.uncompressedSize, UInt32(expected.count))
            XCTAssertEqual(header.crc32, referenceCRC32(expected), "\(header.name) CRC32 mismatch")
            let expectedFlags: UInt16 = header.name.allSatisfy(\.isASCII) ? 0 : 0x800
            XCTAssertEqual(header.flags, expectedFlags, "\(header.name) language encoding flag mismatch")
        }
    }

    func testArchiveRoundTripsThroughSystemUnzip() throws {
        guard let unzip = ["/usr/bin/unzip", "/opt/homebrew/bin/unzip", "/usr/local/bin/unzip"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("unzip is not available on this machine.")
        }
        let (root, files) = try makeSiteTree()
        let archive = try ZipArchive.archiveDirectory(root.url)

        let scratch = try TemporaryDirectory()
        let zipFile = scratch.url.appendingPathComponent("site.zip")
        let extracted = scratch.url.appendingPathComponent("extracted")
        try archive.write(to: zipFile)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: unzip)
        process.arguments = ["-o", zipFile.path, "-d", extracted.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip should extract the archive cleanly")

        for (path, bytes) in files {
            let url = extracted.appendingPathComponent(path)
            XCTAssertEqual(try Data(contentsOf: url), bytes, "\(path) should be byte-identical after extraction")
        }
    }

    func testArchivingEmptyDirectoryThrows() throws {
        let root = try TemporaryDirectory()
        XCTAssertThrowsError(try ZipArchive.archiveDirectory(root.url))
    }

    private func parseLocalFileHeaders(_ archive: Data) throws -> [LocalFileHeader] {
        var headers: [LocalFileHeader] = []
        var offset = 0
        while offset + 4 <= archive.count {
            let signature = readUInt32(archive, at: offset)
            if signature != 0x04034b50 { break }
            let flags = readUInt16(archive, at: offset + 6)
            let method = readUInt16(archive, at: offset + 8)
            let crc = readUInt32(archive, at: offset + 14)
            let compressedSize = readUInt32(archive, at: offset + 18)
            let uncompressedSize = readUInt32(archive, at: offset + 22)
            let nameLength = Int(readUInt16(archive, at: offset + 26))
            let extraLength = Int(readUInt16(archive, at: offset + 28))
            let nameStart = offset + 30
            let name = try XCTUnwrap(String(data: archive.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8))
            let dataStart = nameStart + nameLength + extraLength
            let bytes = archive.subdata(in: dataStart..<(dataStart + Int(compressedSize)))
            headers.append(LocalFileHeader(
                flags: flags,
                compressionMethod: method,
                crc32: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                name: name,
                bytes: bytes
            ))
            offset = dataStart + Int(compressedSize)
        }
        return headers
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }

    private func referenceCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1
            }
        }
        return crc ^ 0xffffffff
    }
}
