import Foundation

enum ZipArchive {
    struct Entry: Sendable {
        var name: String
        var bytes: Data
    }

    private struct EntryCandidate: Sendable {
        var name: String
        var url: URL
    }

    static func archiveDirectory(_ directory: URL) throws -> Data {
        try archive(entries: entries(in: directory))
    }

    static func entries(in directory: URL) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw InksteadWriterError.io("Build output directory \(directory.path) does not exist.")
        }
        let rootPath = directory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else {
            throw InksteadWriterError.io("Could not read build output directory \(directory.path).")
        }
        var candidates: [EntryCandidate] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = file.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : file.lastPathComponent
            guard !relative.isEmpty else { continue }
            candidates.append(EntryCandidate(name: relative.replacingOccurrences(of: "\\", with: "/"), url: file))
        }
        let entries = try BuildConcurrency.map(candidates) { candidate in
            Entry(name: candidate.name, bytes: try Data(contentsOf: candidate.url))
        }
        return entries.sorted { $0.name < $1.name }
    }

    static func archive(entries: [Entry]) throws -> Data {
        guard !entries.isEmpty else {
            throw InksteadWriterError.io("Build output directory does not contain any files to deploy.")
        }

        var output = Data()
        var centralDirectory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            try validateSize(name.count, label: "ZIP file name")
            try validateSize(entry.bytes.count, label: entry.name)
            let offset = output.count
            try validateSize(offset, label: "ZIP offset")
            let crc = CRC32.checksum(entry.bytes)

            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(entry.bytes.count))
            output.appendUInt32(UInt32(entry.bytes.count))
            output.appendUInt16(UInt16(name.count))
            output.appendUInt16(0)
            output.append(name)
            output.append(entry.bytes)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(entry.bytes.count))
            centralDirectory.appendUInt32(UInt32(entry.bytes.count))
            centralDirectory.appendUInt16(UInt16(name.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(UInt32(offset))
            centralDirectory.append(name)
        }

        let centralDirectoryOffset = output.count
        try validateSize(centralDirectoryOffset, label: "ZIP central directory offset")
        try validateSize(centralDirectory.count, label: "ZIP central directory")
        try validateEntryCount(entries.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(UInt32(centralDirectoryOffset))
        output.appendUInt16(0)
        return output
    }

    private static func validateSize(_ value: Int, label: String) throws {
        if value > Int(UInt32.max) {
            throw InksteadWriterError.io("\(label) is too large for ZIP deployment.")
        }
    }

    private static func validateEntryCount(_ count: Int) throws {
        if count > Int(UInt16.max) {
            throw InksteadWriterError.io("ZIP deployment supports at most \(UInt16.max) files.")
        }
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xedb88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
