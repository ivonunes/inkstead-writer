import Foundation

final class FileContentHashCache: @unchecked Sendable {
    static let shared = FileContentHashCache()

    private struct Entry {
        var fileSize: Int
        var modificationDate: Date
        var hash: String
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var storedComputedHashCount = 0

    var computedHashCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedComputedHashCount
    }

    func hash(of url: URL) throws -> String {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values.fileSize ?? -1
        let modificationDate = values.contentModificationDate ?? .distantPast
        let key = standardized.path
        lock.lock()
        if let entry = entries[key], entry.fileSize == fileSize, entry.modificationDate == modificationDate {
            lock.unlock()
            return entry.hash
        }
        lock.unlock()
        let hash = SHA256.hex(try Data(contentsOf: standardized))
        lock.lock()
        entries[key] = Entry(fileSize: fileSize, modificationDate: modificationDate, hash: hash)
        storedComputedHashCount += 1
        lock.unlock()
        return hash
    }
}
