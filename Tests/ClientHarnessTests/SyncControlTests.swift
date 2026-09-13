// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``SyncControl``.
///
/// The calls themselves need a File Provider domain and belong to the live suites. What can be pinned here is the mapping onto the file system's own vocabulary, which is the part where a mistake is silent: asking for the wrong resume behaviour produces a test which passes while testing nothing, because the provider is never asked to detect a conflict at all.
///
@Suite("Sync control")
struct SyncControlTests {
    ///
    /// The distinction the conflict suite rests on. `preserveLocalChanges` permits the server's version to be replaced; only `afterUploadWithFailOnConflict` asks for the conflict to be detected.
    ///
    @Test
    func `Asking to fail on a conflict maps onto the behaviour which does.`() {
        #expect(SyncControl.ResumeBehaviour.failingOnConflict.fileManagerBehaviour == .afterUploadWithFailOnConflict)
        #expect(SyncControl.ResumeBehaviour.preservingLocalChanges.fileManagerBehaviour == .preserveLocalChanges)
        #expect(SyncControl.ResumeBehaviour.droppingLocalChanges.fileManagerBehaviour == .dropLocalChanges)
    }

    ///
    /// Reading the advertised controls of something which is not in a domain must be quiet, because a report is collected precisely when things have gone wrong.
    ///
    @Test
    func `An item outside a domain advertises nothing rather than failing.`() {
        let url = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .notDirectory)

        #expect(SyncControl.supportedControls(of: url) == nil)
        #expect(SyncControl.isPaused(url) == nil)

        // Nothing rather than `false`, and the difference is the point. "The key says this item cannot be paused" and "there is no key to read" are different answers, and answering `false` to the second is what once turned a broken reader into sixteen bug reports about the client.
        #expect(SyncControl.supportsPausing(url) == nil)
        #expect(SyncControl.supportsFailingOnConflict(url) == nil)
    }

    ///
    /// A pause which fails must be recognisable as a pause which failed.
    ///
    /// The whole reason ``SyncControlFailure`` exists: a test which flattens pausing, editing and resuming into one `do` block reports a code and leaves a person to argue about which of the three produced it. That argument cost a day once.
    ///
    @Test
    func `A failure to pause is reported as a failure to pause.`() async throws {
        let url = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try Data().write(to: url)

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        await #expect(throws: SyncControlFailure.self) {
            try await SyncControl.withPaused(url) {
                Issue.record("The body ran even though the item could not be paused.")
            }
        }
    }

    ///
    /// Every documented failure of this family is a wrapper, so a description which stops at the outer error describes nothing.
    ///
    @Test
    func `Describing an error reaches the error inside it and the path it was refused on.`() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 1, userInfo: [:])
        let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
            NSFilePathErrorKey: "/private/tmp/contested.bin",
            NSUnderlyingErrorKey: underlying,
        ])

        let described = SyncControlFailure.describe(error)

        #expect(described.contains("NSCocoaErrorDomain 513"))
        #expect(described.contains("/private/tmp/contested.bin"))
        #expect(described.contains("NSPOSIXErrorDomain 1"))
    }

    ///
    /// Which half failed is the first thing a reader needs, so it belongs in the sentence rather than in a case name nobody prints.
    ///
    @Test
    func `A failure says which half of the pair it came from.`() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [:])

        #expect(SyncControlFailure.pausing(error).description.contains("Pausing"))
        #expect(SyncControlFailure.resuming(error).description.contains("Resuming"))
    }
}
