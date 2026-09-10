// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One way in which a directory on the server and its counterpart in the domain disagree.
///
public enum ConvergenceDifference: Hashable, Sendable, CustomStringConvertible {
    ///
    /// The server has an entry which the domain does not.
    ///
    case missingLocally(name: String)

    ///
    /// The domain has an entry which the server does not.
    ///
    case missingRemotely(name: String)

    ///
    /// Both sides have the entry, but one calls it a directory and the other a file.
    ///
    case kindDiffers(name: String, remoteIsDirectory: Bool, localIsDirectory: Bool)

    ///
    /// Both sides have the file, but its size differs.
    ///
    case sizeDiffers(name: String, remote: Int64, local: Int64)

    ///
    /// Both sides have the entry under names which mean the same but are spelled differently.
    ///
    /// This is the Unicode normalization case: macOS decomposes, the server keeps what it was given. It is reported as its own difference rather than normalized away, because it is a real and recurring bug class.
    ///
    case nameNormalizationDiffers(remote: String, local: String)

    public var description: String {
        switch self {
            case let .missingLocally(name):
                "\"\(name)\" exists on the server but not in the domain."

            case let .missingRemotely(name):
                "\"\(name)\" exists in the domain but not on the server."

            case let .kindDiffers(name, remoteIsDirectory, localIsDirectory):
                "\"\(name)\" is a \(remoteIsDirectory ? "directory" : "file") on the server but a \(localIsDirectory ? "directory" : "file") in the domain."

            case let .sizeDiffers(name, remote, local):
                "\"\(name)\" is \(remote) bytes on the server but \(local) bytes in the domain."

            case let .nameNormalizationDiffers(remote, local):
                "The server spells the name as \"\(remote)\" while the domain spells it as \"\(local)\"."
        }
    }
}
