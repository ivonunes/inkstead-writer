import Foundation

struct HTTPMultipartForm {
    var boundary: String
    private var parts: [Data] = []

    init(boundary: String = "InksteadWriterBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))") {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String, contentType: String? = nil) {
        var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n"
        if let contentType {
            header += "Content-Type: \(contentType)\r\n"
        }
        header += "\r\n"
        parts.append(Data(header.utf8) + Data(value.utf8) + Data("\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, bytes: Data) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8) + bytes + Data("\r\n".utf8))
    }

    func body() -> Data {
        parts.reduce(Data(), +) + Data("--\(boundary)--\r\n".utf8)
    }
}
