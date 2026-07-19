// SPDX-License-Identifier: BSD-3-Clause
// Copyright Contributors to the libjpeg-turbo project

import CTurboJPEG
import Foundation

public enum JPEGTurboError: Error {
    case initializationFailed(String)
    case invalidImageDimensions
    case invalidPixelBuffer
    case decodeFailed(String)
    case encodeFailed(String)
}

public struct JPEGTurboImage {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum JPEGTurbo {
    public static let version = "3.1.4.1"

    public static func dimensions(of data: [UInt8]) throws -> (width: Int, height: Int) {
        try withDecompressor { handle in
            try data.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else {
                    throw JPEGTurboError.invalidPixelBuffer
                }
                guard tj3DecompressHeader(handle, baseAddress, buffer.count) == 0 else {
                    throw JPEGTurboError.decodeFailed(errorMessage(for: handle))
                }
                let width = Int(tj3Get(handle, cInt(TJPARAM_JPEGWIDTH.rawValue)))
                let height = Int(tj3Get(handle, cInt(TJPARAM_JPEGHEIGHT.rawValue)))
                guard width > 0, height > 0 else {
                    throw JPEGTurboError.invalidImageDimensions
                }
                return (width, height)
            }
        }
    }

    public static func decode(_ data: [UInt8]) throws -> JPEGTurboImage {
        try withDecompressor { handle in
            try data.withUnsafeBufferPointer { buffer in
                guard let source = buffer.baseAddress, !buffer.isEmpty else {
                    throw JPEGTurboError.invalidPixelBuffer
                }
                guard tj3DecompressHeader(handle, source, buffer.count) == 0 else {
                    throw JPEGTurboError.decodeFailed(errorMessage(for: handle))
                }
                let width = Int(tj3Get(handle, cInt(TJPARAM_JPEGWIDTH.rawValue)))
                let height = Int(tj3Get(handle, cInt(TJPARAM_JPEGHEIGHT.rawValue)))
                guard width > 0, height > 0 else {
                    throw JPEGTurboError.invalidImageDimensions
                }

                var rgba = [UInt8](repeating: 0, count: width * height * 4)
                let result = rgba.withUnsafeMutableBufferPointer { destination in
                    tj3Decompress8(handle, source, buffer.count, destination.baseAddress, 0, cInt(TJPF_RGBA.rawValue))
                }
                guard result == 0 || tj3GetErrorCode(handle) == cInt(TJERR_WARNING.rawValue) else {
                    throw JPEGTurboError.decodeFailed(errorMessage(for: handle))
                }
                return JPEGTurboImage(width: width, height: height, rgba: rgba)
            }
        }
    }

    public static func encodeRGB(width: Int, height: Int, rgb: [UInt8], quality: Int) throws -> [UInt8] {
        guard width > 0, height > 0 else {
            throw JPEGTurboError.invalidImageDimensions
        }
        guard rgb.count == width * height * 3 else {
            throw JPEGTurboError.invalidPixelBuffer
        }

        return try withCompressor { handle in
            guard tj3Set(handle, cInt(TJPARAM_QUALITY.rawValue), Int32(max(1, min(100, quality)))) == 0,
                  tj3Set(handle, cInt(TJPARAM_SUBSAMP.rawValue), cInt(TJSAMP_420.rawValue)) == 0,
                  tj3Set(handle, cInt(TJPARAM_FASTDCT.rawValue), 1) == 0 else {
                throw JPEGTurboError.encodeFailed(errorMessage(for: handle))
            }

            var jpegBuffer: UnsafeMutablePointer<UInt8>?
            var jpegSize = 0
            defer { tj3Free(jpegBuffer) }

            let result = rgb.withUnsafeBufferPointer { source in
                tj3Compress8(
                    handle,
                    source.baseAddress,
                    Int32(width),
                    0,
                    Int32(height),
                    cInt(TJPF_RGB.rawValue),
                    &jpegBuffer,
                    &jpegSize
                )
            }
            guard result == 0, let jpegBuffer else {
                throw JPEGTurboError.encodeFailed(errorMessage(for: handle))
            }
            return [UInt8](UnsafeBufferPointer(start: jpegBuffer, count: jpegSize))
        }
    }

    private static func withDecompressor<T>(_ body: (tjhandle) throws -> T) throws -> T {
        guard let handle = tjInitCompat(cInt(TJINIT_DECOMPRESS.rawValue)) else {
            throw JPEGTurboError.initializationFailed(errorMessage(for: nil))
        }
        defer { tj3Destroy(handle) }
        return try body(handle)
    }

    private static func withCompressor<T>(_ body: (tjhandle) throws -> T) throws -> T {
        guard let handle = tjInitCompat(cInt(TJINIT_COMPRESS.rawValue)) else {
            throw JPEGTurboError.initializationFailed(errorMessage(for: nil))
        }
        defer { tj3Destroy(handle) }
        return try body(handle)
    }

    private static func errorMessage(for handle: tjhandle?) -> String {
        guard let error = tj3GetErrorStr(handle) else {
            return "Unknown libjpeg-turbo error"
        }
        return String(cString: error)
    }

    private static func cInt(_ value: UInt32) -> Int32 {
        Int32(value)
    }

    private static func cInt(_ value: Int32) -> Int32 {
        value
    }
}
