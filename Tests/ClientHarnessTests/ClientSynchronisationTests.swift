// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``ClientSynchronisation``.
///
/// These are hermetic and therefore cannot flip the real value: writing it would block the desktop client of whoever ran a bare `swift test`, which is exactly the accident the whole safety net around this feature exists to prevent. What is pinned here is the vocabulary the client and the harness have to agree on, and the reading of what the `defaults` tool reports back. The behaviour of blocking itself belongs to the live suites.
///
@Suite("Client synchronisation")
struct ClientSynchronisationTests {
    ///
    /// The key is a contract with the desktop client, which reads it under this exact spelling. Changing it on one side only would produce a harness which believes it has blocked a client which carries on synchronising.
    ///
    @Test
    func `The key is spelled the way the desktop client reads it.`() {
        #expect(ClientSynchronisation.key == "blockSync")
    }

    ///
    /// The extension is sandboxed, so its preferences live in its own container rather than in the group container. Writing to the client's own domain instead would silently do nothing.
    ///
    @Test
    func `The value belongs to the File Provider extension rather than to the client.`() {
        #expect(ClientPaths.fileProviderExtensionBundleIdentifier == "com.nextcloud.desktopclient.FileProviderExt")
        #expect(ClientPaths.fileProviderExtensionBundleIdentifier != ClientPaths.bundleIdentifier)
    }

    @Test
    func `The defaults tool is where the operating system keeps it.`() {
        #expect(FileManager.default.isExecutableFile(atPath: ExtensionDefaults.executable.path(percentEncoded: false)))
    }

    ///
    /// Both switches live in the same preference domain and are read live by the extension, which is why they share their plumbing. They must not share a key.
    ///
    @Test
    func `Blocking and debug logging are separate switches.`() {
        #expect(ClientLogging.debugLoggingKey == "debugLoggingEnabled")
        #expect(ClientLogging.debugLoggingKey != ClientSynchronisation.key)
    }

    ///
    /// Debug logging belongs to a run rather than to the machine, so a harness which leaves it on fills somebody's disk long after the run is forgotten.
    ///
    @Test
    func `A machine which was never given debug logging reports it as off.`() async {
        #expect(await ClientLogging.isDebugLoggingEnabled() == false)
    }

    ///
    /// Reading a machine which was never blocked must be quiet rather than an error. A preflight which failed on every machine where the client has not run yet would be worse than no preflight.
    ///
    @Test
    func `A machine which was never blocked reports as not blocked.`() async {
        #expect(await ClientSynchronisation.isBlocked() == false)
    }

    ///
    /// Unblocking runs on every way out of a scope, including those which never blocked anything, so it has to tolerate the value not being there. The `defaults` tool fails in that case, and confusingly reports that the whole domain was not found.
    ///
    @Test
    func `Unblocking a machine which is not blocked is not an error.`() async throws {
        try await ClientSynchronisation.unblock()
    }
}
