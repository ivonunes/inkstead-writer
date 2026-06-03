import Foundation

public struct InksteadWriterVersion: Comparable, Equatable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var raw: String

    public init(_ raw: String) {
        self.raw = raw
        let numeric = raw.split(separator: "-", maxSplits: 1).first.map(String.init) ?? raw
        let parts = numeric.split(separator: ".").map { Int($0) ?? 0 }
        major = parts.indices.contains(0) ? parts[0] : 0
        minor = parts.indices.contains(1) ? parts[1] : 0
        patch = parts.indices.contains(2) ? parts[2] : 0
    }

    public var description: String { raw }

    public static func < (lhs: InksteadWriterVersion, rhs: InksteadWriterVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
