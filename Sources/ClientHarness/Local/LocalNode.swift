// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One file system object inside a File Provider domain, described without touching its contents.
///
/// Everything here comes from `lstat`, which neither materializes a file nor enumerates a directory. That matters: reading a dataless file would download it, and enumerating a directory is what drives the extension's enumerator for that container. Both are events the tests want to trigger deliberately, never as a side effect of looking at something.
///
public struct LocalNode: Hashable, Sendable {
    ///
    /// The bit in `st_flags` macOS sets on a dataless placeholder, from `SF_DATALESS` in `sys/stat.h`.
    ///
    /// It is spelled out here rather than imported so that the meaning of the check is visible at the place it is made.
    ///
    public static let datalessFlag: UInt32 = 0x4000_0000

    ///
    /// The flags reported in `st_flags`, kept whole for diagnostics.
    ///
    public let flags: UInt32

    ///
    /// Whether the object is a dataless placeholder rather than a materialized file.
    ///
    /// Directories inside a replicated domain are dataless too until their contents have been fetched, so this is only meaningful together with ``kind``.
    ///
    public var isDataless: Bool {
        flags & Self.datalessFlag != 0
    }

    ///
    /// What kind of object this is.
    ///
    public let kind: LocalNodeKind

    ///
    /// The point in time the object was last modified, as the file system reports it.
    ///
    public let modificationDate: Date

    ///
    /// The last path component of ``url``.
    ///
    public var name: String {
        url.lastPathComponent
    }

    ///
    /// The logical size in bytes.
    ///
    /// A dataless placeholder reports the size of the file it stands for while occupying no blocks, which is exactly why size alone never proves that content arrived.
    ///
    public let size: Int64

    ///
    /// The number of 512 byte blocks actually allocated on disk.
    ///
    /// This is the second, independent signal for materialization: a placeholder occupies none.
    ///
    public let allocatedBlocks: Int64

    ///
    /// Where the object is.
    ///
    public let url: URL

    ///
    /// Describe the object at a location, without following symbolic links.
    ///
    /// - Parameters:
    ///     - url: The location to describe.
    ///
    /// - Returns: The description, or `nil` if nothing is there.
    ///
    /// - Throws: ``LocalInspectionError`` if the system would not say what is there, which is not the same answer as nothing being there.
    ///
    public static func at(_ url: URL) throws -> LocalNode? {
        var status = stat()
        let path = url.path(percentEncoded: false)

        guard lstat(path, &status) == 0 else {
            // Only these two mean the location is empty. Every other errno means the question was not answered, and returning `nil` for those is how "the process was not allowed to look" became "there is nothing there" throughout this suite.
            guard errno == ENOENT || errno == ENOTDIR else {
                throw LocalInspectionError(path: path, code: errno)
            }

            return nil
        }

        let kind: LocalNodeKind = switch status.st_mode & S_IFMT {
            case S_IFDIR:
                .directory

            case S_IFREG:
                .file

            case S_IFLNK:
                .symbolicLink

            default:
                .other
        }

        return LocalNode(
            url: url,
            kind: kind,
            size: Int64(status.st_size),
            allocatedBlocks: Int64(status.st_blocks),
            modificationDate: Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec) + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000),
            flags: status.st_flags
        )
    }

    ///
    /// Create a description of a file system object.
    ///
    /// - Parameters:
    ///     - url: Where the object is.
    ///     - kind: What kind of object it is.
    ///     - size: The logical size in bytes.
    ///     - allocatedBlocks: The number of 512 byte blocks allocated on disk.
    ///     - modificationDate: When the object was last modified.
    ///     - flags: The flags reported in `st_flags`.
    ///
    public init(url: URL, kind: LocalNodeKind, size: Int64, allocatedBlocks: Int64, modificationDate: Date, flags: UInt32) {
        self.allocatedBlocks = allocatedBlocks
        self.flags = flags
        self.kind = kind
        self.modificationDate = modificationDate
        self.size = size
        self.url = url
    }
}
