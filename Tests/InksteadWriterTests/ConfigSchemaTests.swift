import Foundation
import XCTest
@testable import InksteadWriter

final class ConfigSchemaTests: XCTestCase {
    private var schemaURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("support/inkstead-writer.schema.json")
    }

    func testSchemaDeclaresEveryConfigKey() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        XCTAssertEqual(schema["$id"] as? String, InksteadWriterMetadata.configSchemaURL)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let declared = Set(InksteadWriterConfig.CodingKeys.allCases.map(\.stringValue))
        XCTAssertEqual(declared.subtracting(properties.keys), [])
        XCTAssertEqual(Set(properties.keys).subtracting(declared), [])
    }

    func testGeneratedConfigPointsAtSchemaAndStillDecodes() throws {
        let parent = try TemporaryDirectory()
        let site = parent.url.appendingPathComponent("site")
        _ = try SiteInitializer.initSite(at: site, options: InitSiteOptions(ci: nil, deploy: nil, syndication: []))

        let text = try String(contentsOf: site.appendingPathComponent(InksteadWriterMetadata.configFileName), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("{\n  \"$schema\" : "), text)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(json["$schema"] as? String, InksteadWriterMetadata.configSchemaURL)
        XCTAssertNoThrow(try ConfigLoader.load(root: site))
    }
}
