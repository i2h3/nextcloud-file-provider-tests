// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Rainmaker

///
/// Reads one directory level from the server for comparison with the client.
///
/// The listing is translated into ``RemoteEntry`` values so that ``ConvergenceCheck`` can stay in ``ClientHarness``, which knows nothing about Nextcloud and can therefore be unit tested without a server.
///
public enum RemoteListing {
    ///
    /// List the children of a directory on the server.
    ///
    /// - Parameters:
    ///     - path: The directory to list, relative to the user's files root.
    ///     - server: The client to ask.
    ///
    /// - Returns: The children, without the directory itself.
    ///
    /// - Throws: Whatever the request raises.
    ///
    public static func children(of path: String, on server: Server) async throws -> [RemoteEntry] {
        let items: [Item] = try await server.enumerate(at: path, recursively: false)
        let containerPath = normalized(path)

        return items
            .filter { normalized($0.path) != containerPath }
            .map {
                // `instanceId` is `oc:fileid` and `id` is `oc:id`, which is the opposite of what both names suggest. The identity which survives a rename is the former, and asserting on the latter would produce a test passing for the wrong reason.
                RemoteEntry(
                    name: $0.name,
                    isDirectory: $0.isDirectory,
                    size: $0.isDirectory ? nil : Int64($0.size),
                    fileIdentifier: $0.instanceId,
                    entityTag: $0.entityTag,
                    modifiedAt: $0.modification
                )
            }
    }

    ///
    /// Reduce a path to a form which can be compared.
    ///
    /// - Parameters:
    ///     - path: The path to reduce.
    ///
    /// - Returns: The path without surrounding slashes.
    ///
    private static func normalized(_ path: String) -> String {
        var normalized = path

        while normalized.hasPrefix("/") {
            normalized.removeFirst()
        }

        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }
}
