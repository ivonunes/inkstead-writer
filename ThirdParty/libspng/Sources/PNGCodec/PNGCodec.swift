// SPDX-License-Identifier: BSD-2-Clause
// Copyright (c) 2018-2024 Randy

import CSPNG
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PNGCodecError: Error {
    case initializationFailed
    case invalidImageDimensions
    case invalidPixelBuffer
    case decodeFailed(String)
    case encodeFailed(String)
}

public struct PNGCodecImage {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum PNGCodec {
    public static let version = "0.7.4"

    public static func dimensions(of data: [UInt8]) throws -> (width: Int, height: Int) {
        try withDecoder(for: data) { context in
            var header = spng_ihdr()
            let result = spng_get_ihdr(context, &header)
            guard result == 0 else {
                throw PNGCodecError.decodeFailed(errorMessage(result))
            }
            return try dimensions(from: header)
        }
    }

    public static func decode(_ data: [UInt8]) throws -> PNGCodecImage {
        try withDecoder(for: data) { context in
            var header = spng_ihdr()
            let headerResult = spng_get_ihdr(context, &header)
            guard headerResult == 0 else {
                throw PNGCodecError.decodeFailed(errorMessage(headerResult))
            }
            let size = try dimensions(from: header)

            var outputSize = 0
            let sizeResult = spng_decoded_image_size(context, cInt(SPNG_FMT_RGBA8.rawValue), &outputSize)
            guard sizeResult == 0 else {
                throw PNGCodecError.decodeFailed(errorMessage(sizeResult))
            }
            guard outputSize == size.width * size.height * 4 else {
                throw PNGCodecError.invalidImageDimensions
            }

            var rgba = [UInt8](repeating: 0, count: outputSize)
            let decodeResult = rgba.withUnsafeMutableBufferPointer { output in
                spng_decode_image(
                    context,
                    output.baseAddress,
                    output.count,
                    cInt(SPNG_FMT_RGBA8.rawValue),
                    cInt(SPNG_DECODE_TRNS.rawValue)
                )
            }
            guard decodeResult == 0 else {
                throw PNGCodecError.decodeFailed(errorMessage(decodeResult))
            }
            return PNGCodecImage(width: size.width, height: size.height, rgba: rgba)
        }
    }

    public static func encodeRGBA(width: Int, height: Int, rgba: [UInt8], compressionLevel: Int = 3) throws -> [UInt8] {
        guard width > 0, height > 0,
              width <= Int(UInt32.max),
              height <= Int(UInt32.max) else {
            throw PNGCodecError.invalidImageDimensions
        }
        guard rgba.count == width * height * 4 else {
            throw PNGCodecError.invalidPixelBuffer
        }

        guard let context = spng_ctx_new(cInt(SPNG_CTX_ENCODER.rawValue)) else {
            throw PNGCodecError.initializationFailed
        }
        defer { spng_ctx_free(context) }

        var result = spng_set_option(context, SPNG_ENCODE_TO_BUFFER, 1)
        guard result == 0 else {
            throw PNGCodecError.encodeFailed(errorMessage(result))
        }

        let level = max(0, min(9, compressionLevel))
        result = spng_set_option(context, SPNG_IMG_COMPRESSION_LEVEL, Int32(level))
        guard result == 0 else {
            throw PNGCodecError.encodeFailed(errorMessage(result))
        }

        var header = spng_ihdr(
            width: UInt32(width),
            height: UInt32(height),
            bit_depth: 8,
            color_type: UInt8(SPNG_COLOR_TYPE_TRUECOLOR_ALPHA.rawValue),
            compression_method: 0,
            filter_method: 0,
            interlace_method: 0
        )
        result = spng_set_ihdr(context, &header)
        guard result == 0 else {
            throw PNGCodecError.encodeFailed(errorMessage(result))
        }

        result = rgba.withUnsafeBufferPointer { source in
            spng_encode_image(
                context,
                source.baseAddress,
                source.count,
                cInt(SPNG_FMT_PNG.rawValue),
                cInt(SPNG_ENCODE_FINALIZE.rawValue)
            )
        }
        guard result == 0 else {
            throw PNGCodecError.encodeFailed(errorMessage(result))
        }

        var outputSize = 0
        var bufferResult: Int32 = 0
        guard let output = spng_get_png_buffer(context, &outputSize, &bufferResult) else {
            throw PNGCodecError.encodeFailed(errorMessage(bufferResult))
        }
        defer { free(output) }

        return [UInt8](UnsafeBufferPointer(start: output.assumingMemoryBound(to: UInt8.self), count: outputSize))
    }

    private static func withDecoder<T>(for data: [UInt8], _ body: (OpaquePointer) throws -> T) throws -> T {
        try data.withUnsafeBufferPointer { buffer in
            guard let source = buffer.baseAddress, !buffer.isEmpty else {
                throw PNGCodecError.invalidPixelBuffer
            }
            guard let context = spng_ctx_new(0) else {
                throw PNGCodecError.initializationFailed
            }
            defer { spng_ctx_free(context) }

            let result = spng_set_png_buffer(context, source, buffer.count)
            guard result == 0 else {
                throw PNGCodecError.decodeFailed(errorMessage(result))
            }
            return try body(context)
        }
    }

    private static func dimensions(from header: spng_ihdr) throws -> (width: Int, height: Int) {
        let width = Int(header.width)
        let height = Int(header.height)
        guard width > 0, height > 0 else {
            throw PNGCodecError.invalidImageDimensions
        }
        return (width, height)
    }

    private static func errorMessage(_ code: Int32) -> String {
        guard let error = spng_strerror(code) else {
            return "Unknown libspng error"
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
