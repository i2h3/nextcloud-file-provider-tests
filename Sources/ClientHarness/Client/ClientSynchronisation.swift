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
    /// - Throws: ``ClientSynchronisationError/notUnblocked`` if the client is still blocked afterwards, or ``ClientSynchronisationError/blockStateUnreadable`` if that could not be determined.
    ///
    public static func unblock() async throws {
        var detail = "it could not be read at all"
        let deadline = ContinuousClock.now + confirmationWindow

        while true {
            switch await ExtensionDefaults.clear(key) {
                case .off:
                    return

                case .on:
                    throw ClientSynchronisationError.notUnblocked

                case let .unreadable(said):
                    // The state that used to be success. Reading the switch back is the whole of this method's confirmation, and a read which could not happen confirmed nothing while returning `false` for "is it on" — so a machine whose defaults are unreadable left every room believing it had unblocked a client it had not.
                    //
                    // Retried rather than raised at once, because this runs immediately after the client has been told to quit and the first time it fired it was gone by the time anyone looked. The preferences of a sandboxed extension are served by a daemon which is tearing that container down at exactly this moment, and a refusal during a teardown is not the same as a refusal by policy. Retrying an assertion would be dishonest; this is not one — it is the harness putting the machine into a known state before any measurement is taken.
                    detail = said
            }

            guard ContinuousClock.now < deadline else {
                throw ClientSynchronisationError.blockStateUnreadable(detail)
            }

            try await Task.sleep(for: .milliseconds(250))
        }
    }

    ///
    /// How long unblocking keeps trying to confirm itself before giving up.
    ///
    /// Long enough to outlast a preferences daemon releasing a container it has just been asked to tear down, short enough that a machine genuinely missing the grant says so while somebody is still watching.
    ///
    public static let confirmationWindow = Duration.seconds(10)

    ///
    /// Whether the client is currently blocked from synchronising.
    ///
    /// - Returns: `true` only if the key is present and reads as true. A machine whose defaults cannot be read at all is reported as not blocked, because the alternative is a preflight which fails on every machine where the client has never run.
    ///
    public static func isBlocked() async -> Bool {
        await ExtensionDefaults.isEnabled(key)
    }
}
