// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

///
/// Produces the file content the tests upload and compare.
///
/// Content is generated from a seed rather than read from committed fixtures, and it is generated deterministically, so that a mismatch can be diagnosed: the same seed and size always yield the same bytes, on every machine and in every run. Nothing here depends on the demo content a Nextcloud server ships, which is deliberately switched off for every server under test.
///
public enum ContentFactory {
    ///
    /// Produce content of a given size.
    ///
    /// - Parameters:
    ///     - size: How many bytes to produce.
    ///     - seed: The seed determining the bytes. The same seed and size always produce the same content.
    ///
    /// - Returns: The produced content.
    ///
    public static func content(size: Int, seed: UInt64) -> Data {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        var bytes = [UInt8]()
        bytes.reserveCapacity(size)

        while bytes.count < size {
            state = next(&state)
            withUnsafeBytes(of: state.littleEndian) { buffer in
                for byte in buffer where bytes.count < size {
                    bytes.append(byte)
                }
            }
        }

        return Data(bytes)
    }

    ///
    /// The fingerprint of some content, for comparing what was uploaded with what arrived.
    ///
    /// - Parameters:
    ///     - content: The content to fingerprint.
    ///
    /// - Returns: The hexadecimal SHA-256 digest.
    ///
    public static func fingerprint(of content: Data) -> String {
        SHA256.hash(data: content)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    ///
    /// The fingerprint of a file, read without any caching.
    ///
    /// Reading a file inside a File Provider domain materializes it, which is the point wherever this is used, but never a side effect to be surprised by.
    ///
    /// - Parameters:
    ///     - url: The file to fingerprint.
    ///
    /// - Returns: The hexadecimal SHA-256 digest.
    ///
    /// - Throws: Whatever reading the file raises.
    ///
    public static func fingerprintOfFile(at url: URL) throws -> String {
        try fingerprint(of: Data(contentsOf: url, options: [.uncached]))
    }

    ///
    /// Advance the generator.
    ///
    /// This is SplitMix64, chosen because it is a handful of lines, has no state beyond a single word, and produces the same sequence everywhere.
    ///
    /// - Parameters:
    ///     - state: The state to advance.
    ///
    /// - Returns: The next value.
    ///
    private static func next(_ state: inout UInt64) -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB

        return value ^ (value >> 31)
    }
}
