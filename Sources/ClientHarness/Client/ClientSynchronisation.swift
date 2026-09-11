// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Blocks and unblocks the desktop client's synchronisation with the server.
///
/// The client's File Provider extension reads a process-global `blockSync` boolean from its own user defaults. While it is set, the extension performs no network input or output: every request the system makes of it which would need the server is refused with `NSFileProviderErrorServerUnreachable`, in both directions. Removing the key lets it synchronise again, and the extension notices immediately rather than at the next restart.
///
/// This is the tool for producing divergence on purpose. Suspending the server container — see `ServerWorkspace.withServerPaused` in the test target — takes the server away from the tests as well as from the client, so the remote half of a conflict cannot be created while it is suspended. Blocking the client leaves the server fully available to the test.
///
/// The value is written with the `defaults` tool rather than through `UserDefaults`, because the extension is sandboxed and its preferences live inside its own container. `defaults` reaches that container; a `UserDefaults` suite opened from this process would not.
///
public enum ClientSynchronisation {
    ///
    /// The user defaults key the extension reads.
    ///
    public static let key = "blockSync"

    ///
    /// Stop the client from synchronising.
    ///
    /// - Throws: ``ProcessRunnerError`` if the value cannot be written.
    ///
    public static func block() async throws {
        try await ExtensionDefaults.enable(key)
    }

    ///
    /// Let the client synchronise again.
    ///
    /// The key is removed rather than set to `false`, so that a machine which is not blocked is indistinguishable from one which never was. A leftover `false` would read the same to the client but would make ``isBlocked()`` and the run inventory report a machine which had been meddled with.
    ///
    /// Unblocking runs on every way out of a scope, including those which never blocked anything, so the outcome is checked rather than the exit status — see ``ExtensionDefaults/clear(_:)``.
    ///
    /// - Throws: ``ClientSynchronisationError/notUnblocked`` if the client is still blocked afterwards.
    ///
    public static func unblock() async throws {
        guard await ExtensionDefaults.clear(key) else {
            throw ClientSynchronisationError.notUnblocked
        }
    }

    ///
    /// Whether the client is currently blocked from synchronising.
    ///
    /// - Returns: `true` only if the key is present and reads as true. A machine whose defaults cannot be read at all is reported as not blocked, because the alternative is a preflight which fails on every machine where the client has never run.
    ///
    public static func isBlocked() async -> Bool {
        await ExtensionDefaults.isEnabled(key)
    }
}
