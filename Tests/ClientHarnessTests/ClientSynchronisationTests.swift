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
    /// Reading must be quiet rather than an error, whatever the machine says. A preflight which failed on every machine where the client has never run would be worse than no preflight.
    ///
    /// What is not asserted here is the answer. These read the real user defaults of whichever machine runs them, so an expectation about the value would be an expectation about that machine — which is how this test began, and how it started failing on a machine where a run had left debug logging on.
    ///
    @Test
    func `Reading whether the client is blocked or logging never raises.`() async {
        _ = await ClientSynchronisation.isBlocked()
        _ = await ClientLogging.isDebugLoggingEnabled()
    }

    ///
    /// Unblocking runs on every way out of a scope, including those which never blocked anything, so it has to tolerate the value not being there. The `defaults` tool fails in that case, and confusingly reports that the whole domain was not found.
    ///
    @Test
    func `Unblocking a machine which is not blocked is not an error.`() async throws {
        try await ClientSynchronisation.unblock()
    }

    ///
    /// The two ways macOS says a default is not set.
    ///
    /// Pinned because they are its wording, not ours, and everything downstream turns on telling them apart from a refusal. `unblock()` confirms its own work by reading the switch back; if a release reworded these, every machine would start reading as unreadable and every room would throw before running a test. The opposite mistake is the one this replaced — a read which could not happen counting as the switch being absent, so unblocking confirmed itself by failing to look.
    ///
    @Test
    func `Every way defaults reports an absent value is read as absent.`() {
        // The domain exists and the key does not.
        #expect(ExtensionDefaults.isAbsence("The domain/default pair of (com.example.app, someKey) does not exist"))

        // The domain itself does not exist, which is a machine where the extension has never run.
        #expect(ExtensionDefaults.isAbsence("Error: Domain 'com.nextcloud.desktopclient.FileProviderExt' not found."))

        // The same absence as the first, by another of the tool's own code paths. This one was missing, and a staged run found it at the first attempt — the domain had been created by a client which had run, and the key had not been written.
        #expect(ExtensionDefaults.isAbsence("Error: Could not find key 'blockSync' in domain 'com.nextcloud.desktopclient.FileProviderExt'."))
    }

    ///
    /// Anything else is a failure to look, and must not be mistaken for a value which is not there.
    ///
    @Test
    func `A refusal is not read as an absent value.`() {
        #expect(!ExtensionDefaults.isAbsence("Operation not permitted"))
        #expect(!ExtensionDefaults.isAbsence(""))
        #expect(!ExtensionDefaults.isAbsence("kCFPreferencesAnyApplication: permission denied"))

        // The distinction the whole family rests on: a thing which is missing, against a look which was refused. "Denied" and "not permitted" are the second, whatever they are said about.
        #expect(!ExtensionDefaults.isAbsence("Error: access to domain 'com.example.app' was denied."))
    }

    ///
    /// On a machine where the extension has never run the domain is simply absent, which is not a problem and must not be reported as one.
    ///
    @Test
    func `A machine with no extension domain reads the switch as off rather than unreadable.`() async {
        guard case let .unreadable(said) = await ExtensionDefaults.state(of: ClientSynchronisation.key) else {
            return
        }

        Issue.record("""
        Reading the switch on this machine could not say whether it is set, which on a machine where the extension has never run should read as absent. What it said: \(said)
        """)
    }

    ///
    /// An unreadable state carries what the tool complained about, because the first time this fired it did not and nobody could say why.
    ///
    @Test
    func `A state which could not be read says what was said instead.`() {
        #expect(ExtensionDefaults.quoted("Error: Domain 'x' not found.", or: "") == "\"Error: Domain 'x' not found.\"")
        #expect(ExtensionDefaults.quoted("  ", or: "something on stdout") == "\"something on stdout\" on its output")
        #expect(ExtensionDefaults.quoted("", or: "") == "nothing at all")
    }
}
