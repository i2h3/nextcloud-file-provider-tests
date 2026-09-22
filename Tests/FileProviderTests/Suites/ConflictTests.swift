// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// What happens when the same file is changed on both sides before either side hears about the other.
///
/// This is the group where a mistake costs a user their work rather than their patience, and it is also the group this suite got wrong once, in a way worth writing down.
///
/// The first version of it blocked the client, changed both sides, unblocked, and reported the local version winning as a defect. It was not one. macOS asks a provider to fail an upload on a conflict **only when an application asked for that treatment**: an application pauses the item it has open, and resumes with `NSFileManagerResumeSyncBehaviorAfterUploadWithFailOnConflict` once the document is stable. Without that the documented behaviour is `preserveLocalChanges`, under which the local version is uploaded and the server "may create a conflict copy, or may automatically pick the winner". A test which arranges a divergence and simply waits is measuring that default. It is entitled to no opinion about which of the two permitted outcomes happens, and calling one of them a bug is a bug in the test.
///
/// So these tests take the same route a document-based application takes, through ``SyncControl``. It is deterministic, it needs nothing of the client, and — the point — it is the only way to ask the provider for conflict detection at all.
///
@Suite("Conflicts", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(10)))
struct ConflictTests {
    ///
    /// Put a file on the server and bring its content onto disk.
    ///
    /// - Parameters:
    ///     - room: The room to work in.
    ///     - name: The name to give it.
    ///
    /// - Returns: Its location on disk.
    ///
    /// - Throws: Whatever uploading, waiting or materializing raises.
    ///
    private func makeContestedFile(in room: CleanRoom, named name: String) async throws -> URL {
        try await ServerWorkspace.withFixture(named: name, size: 16 * 1024, seed: 61) { source, _ in
            try await room.server.upload(source, to: "/", force: true)
        }

        try await Waiter.waitUntil("\"\(name)\" appears in the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
            try room.localChildren().contains { $0.name == name }
        }

        let file = room.localURL(of: name)
        _ = try Materialization.materialize(file)

        return file
    }

    ///
    /// Whether the client says it can be asked to detect conflicts at all.
    ///
    /// Worth asserting rather than assuming. A provider which handles the conflict error but never advertises the capability has written code no application is permitted to reach, and an application checking this key would conclude the flow is unavailable and never use it.
    ///
    @Test(arguments: LiveEnvironment.servers)
    func `The client says whether it can pause an item and fail an upload on a conflict.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Conflict.advertisedControls") { room in
            let file = try await makeContestedFile(in: room, named: "advertised.bin")

            // Required rather than expected, and that distinction is the whole lesson of this suite's worst day. A key which cannot be read says nothing about the client, and an assertion which treats the two alike turns a broken reader into a finished bug report.
            let controls = try #require(SyncControl.supportedControls(of: file), """
            The sync-control key could not be read at all for this item, so this run cannot say what the client advertises. That is a fault in the reading, not an answer about the client, and nothing below it is evidence of anything.
            """)

            // Printed rather than only asserted, because the raw value is what settles arguments about this key and the assertions below reduce it to two bits.
            print("  note: a file in \(underTest) advertises sync controls \(controls.rawValue).")

            #expect(controls.contains(.pauseSync), """
            The client does not advertise that an item's synchronisation can be paused, so an application following the documented flow would not attempt it.
            """)

            #expect(controls.contains(.failUploadOnConflict), """
            The client does not advertise that an upload can be failed on a conflict. Its handling of that case is then unreachable, because the behaviour is only available on items whose provider advertises support for it.
            """)

            // The other half of the contract, and the reason a puzzling `featureUnsupported` is worth recognising on sight: a regular, non-package directory is excluded from this family outright. A bundle is not, because the system presents one as a single item.
            //
            // Asserted on the raw optional. Asking `supportsPausing(directory) == false` would have passed identically whether the key said no or could not be read, which makes it an expectation nothing can falsify.
            let directory = room.localURL(of: "")

            #expect(SyncControl.supportedControls(of: directory) == nil, """
            A regular directory carries the sync-control key, but pausing one is documented to be refused with `CocoaError.featureUnsupported`. An application reading this key would attempt something that cannot work.
            """)
        }
    }

    ///
    /// The contract itself.
    ///
    @Test(arguments: LiveEnvironment.servers)
    func `A change made while an item was paused does not overwrite a newer server version.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Conflict.failOnConflict") { room in
            let name = "contested.bin"
            let file = try await makeContestedFile(in: room, named: name)

            let localContent = ContentFactory.content(size: 16 * 1024, seed: 62)
            let remoteFingerprint = ContentFactory.fingerprint(of: ContentFactory.content(size: 16 * 1024, seed: 63))

            // An item inherited in a paused state would make every assertion below meaningless, and says nothing about itself unless asked.
            #expect(SyncControl.isPaused(file) == false, "The file was already paused before the test paused it, so something earlier left it that way.")

            var resumeError: (any Error)?

            do {
                // Inside this the item is out of the provider's reach, which is what lets the two sides diverge on purpose rather than by luck. Writing to it while paused is the designed flow rather than a trick: pausing exists so that an open document can be edited without synchronisation altering it underneath.
                //
                // Asking to resume with `failingOnConflict` is the whole point. It is the only way the provider is told to detect a conflict rather than to overwrite.
                try await SyncControl.withPaused(file, resumingWith: .failingOnConflict) {
                    try localContent.write(to: file)

                    try await ServerWorkspace.withFixture(named: name, size: 16 * 1024, seed: 63) { source, _ in
                        try await room.server.upload(source, to: "/", force: true)
                    }

                    #expect(try await room.remoteFingerprint(of: "/\(name)") == remoteFingerprint, "The server should be holding the remote edit before the item is resumed.")
                }
            } catch let SyncControlFailure.resuming(error) {
                // Refusing to resume is how the provider reports the conflict it was asked to detect, so this is a result rather than a problem.
                resumeError = error
            }

            // Anything else — a failed pause, or a failed write — left this scope already, attributed, rather than arriving here disguised as a conflict.

            guard let resumeError else {
                // Resuming succeeded, so the upload went through. That is only correct if the server had not moved on — and it had.
                let stored = try await room.remoteFingerprint(of: "/\(name)")
                let remote = try await room.remoteChildren()

                #expect(stored == remoteFingerprint || remote.count > 1, """
                Resuming with fail-on-conflict reported success and the local version replaced the newer one on the server, with no conflict copy kept. \
                The server now holds: \(remote.map(\.name).sorted().joined(separator: ", ")).
                """)

                return
            }

            // The documented outcome: the provider refused the upload rather than overwriting, and the application is expected to fetch the newer version and rebase onto it.
            let described = SyncControlFailure.describe(resumeError)
            #expect(described.contains("localVersionConflictingWithServer") || described.contains("Conflict"), "Resuming failed, but not with the conflict the contract describes: \(described)")

            // Whatever happened, the version which was on the server must still be reachable.
            #expect(try await room.remoteFingerprint(of: "/\(name)") == remoteFingerprint, "The server's version was lost even though the upload was refused.")
        }
    }

    ///
    /// The default, recorded as what it is rather than judged.
    ///
    /// This is what the first version of this suite measured and mistook for a defect. Both outcomes it can produce are permitted, so the test asserts only that the file survives and prints which one happened — a change in that is worth noticing, but neither is wrong.
    ///
    @Test(arguments: LiveEnvironment.servers)
    func `Resuming without asking for conflict detection settles on one of the permitted outcomes.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Conflict.preserveLocalChanges") { room in
            let name = "uncontested.bin"
            let file = try await makeContestedFile(in: room, named: name)

            let localContent = ContentFactory.content(size: 16 * 1024, seed: 64)
            let localFingerprint = ContentFactory.fingerprint(of: localContent)
            let remoteFingerprint = ContentFactory.fingerprint(of: ContentFactory.content(size: 16 * 1024, seed: 65))

            #expect(SyncControl.isPaused(file) == false, "The file was already paused before the test paused it, so something earlier left it that way.")

            try await SyncControl.withPaused(file, resumingWith: .preservingLocalChanges) {
                try localContent.write(to: file)

                try await ServerWorkspace.withFixture(named: name, size: 16 * 1024, seed: 65) { source, _ in
                    try await room.server.upload(source, to: "/", force: true)
                }
            }

            // Settled when the two sides agree, which is what every permitted outcome ends in.
            //
            // It used to wait for the server to hold the *client's* version, or for a second file to appear. Those are two of the three permitted outcomes. The third — the server's version winning, with no copy kept — leaves one file holding exactly the bytes the server already held, so the condition was false before anything happened and stayed false: four minutes, then a thrown timeout, for the outcome this test exists to record. A wait which cannot be satisfied by a legal result is an assertion wearing a wait's clothing.
            try await Waiter.poll(
                "the two sides settle on the same content",
                timeout: LiveEnvironment.scaled(.seconds(240)),
                diagnosis: { "the server holding \((try? Data(contentsOf: file)).map { "\($0.count) bytes locally" } ?? "nothing readable locally")" }
            ) {
                let remote = try await room.remoteChildren()

                guard remote.count == 1 else {
                    return true
                }

                let stored = try await room.remoteFingerprint(of: "/\(name)")

                guard let held = try? Data(contentsOf: file) else {
                    return false
                }

                return ContentFactory.fingerprint(of: held) == stored
            }

            let remote = try await room.remoteChildren()
            #expect(!remote.isEmpty, "The file disappeared from the server entirely, which is not one of the permitted outcomes.")

            var fingerprints = [String]()

            for entry in remote {
                try await fingerprints.append(room.remoteFingerprint(of: "/\(entry.name)"))
            }

            // Which of the three happened is the output of this test, and it was a `print`. Two runs a month apart cannot be compared on a line nobody kept, and a client which quietly stopped keeping conflict copies would look identical in the artifacts of both.
            if remote.count > 1 {
                ScenarioOracle.observe("""
                the server kept both versions as a conflict copy: \(remote.map(\.name).sorted().joined(separator: ", "))
                """, in: room)
            } else if fingerprints.contains(localFingerprint) {
                ScenarioOracle.observe("the local version won and the remote edit was not kept separately", in: room)
            } else if fingerprints.contains(remoteFingerprint) {
                ScenarioOracle.observe("the remote version won and the local edit was not kept separately", in: room)
            } else {
                // Neither side's bytes and not a copy. Recorded rather than passed over: the file survived, which is all this test asserts, but what it holds is something no one wrote.
                Issue.record("""
                The file survived the conflict holding bytes neither side wrote. The client wrote one version and the server another, and "\(name)" now matches neither.
                """)
            }
        }
    }
}
