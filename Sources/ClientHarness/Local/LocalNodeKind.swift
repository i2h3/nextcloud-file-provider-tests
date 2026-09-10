// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What kind of file system object a ``LocalNode`` describes.
///
/// Symbolic links are a kind of their own rather than being resolved, because whether the client preserves, rejects or follows them is itself under test.
///
public enum LocalNodeKind: String, Hashable, Sendable {
    ///
    /// A directory, which may or may not have been enumerated yet.
    ///
    case directory

    ///
    /// A regular file, which may be a dataless placeholder or materialized.
    ///
    case file

    ///
    /// A symbolic link, reported without following it.
    ///
    case symbolicLink

    ///
    /// Anything else, such as a socket or a device node.
    ///
    case other
}
