// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads the extended attributes macOS hangs off a File Provider item.
///
/// One of them is evidence rather than metadata. When an item arrives whose name differs from a sibling's only by case, a case-insensitive volume cannot hold both, and the system renames the arriving one — a *bounce*. What it bounced from is recorded in `com.apple.fileprovider.before-bounce#PX`, and that attribute is the only thing which says which name was rejected rather than merely that two names collided.
///
/// Nothing else here needs extended attributes, which is why this is small and stays small.
///
public enum ExtendedAttribute {
    ///
    /// The attribute recording the name an item had before the system renamed it to avoid a collision.
    ///
    public static let beforeBounce = "com.apple.fileprovider.before-bounce#PX"

    ///
    /// Read one attribute of a file.
    ///
    /// - Parameters:
    ///     - name: The attribute.
    ///     - url: The file.
    ///
    /// - Returns: The value, or `nil` where the file has no such attribute.
    ///
    public static func value(of name: String, at url: URL) -> Data? {
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, 0)

        guard size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, 0)

        guard read > 0 else {
            return nil
        }

        return Data(buffer.prefix(read))
    }

    ///
    /// Read one attribute of a file as text.
    ///
    /// - Parameters:
    ///     - name: The attribute.
    ///     - url: The file.
    ///
    /// - Returns: The value, or `nil` where the file has no such attribute or it is not text.
    ///
    public static func string(of name: String, at url: URL) -> String? {
        value(of: name, at: url).flatMap { String(data: $0, encoding: .utf8) }
    }
}
