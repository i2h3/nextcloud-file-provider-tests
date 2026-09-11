// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// What happens when the same file is changed on both sides before either side hears about the other.
///
/// This is the group where a mistake costs a user their work rather than their patience, and it is the reason the client can be blocked from synchronising at all: a conflict needs the client holding a change the server has not seen while the server holds a different one, and there is no way to arrange that while the client is talking to the server. Suspending the container does not help either, because it takes the server away from this suite as well, leaving no way to make the remote change.
///
/// The assertion is deliberately not about the name of a conflict file. On macOS 26 and newer the client answers a rejected upload with `NSFileProviderErrorLocalVersionConflictingWithServer` and **the operating system** creates the copy, so the naming is Apple's rather than Nextcloud's — and it only happens when the system asked for that treatment by passing `.failOnConflict`, which is its decision and not the client's. On older systems there is no conflict-copy contract at all and the client instead fails the upload transiently so that the modification is re-driven against a refreshed base.
///
/// What holds in every one of those cases is the property worth testing: **the version which was already on the server is not silently replaced by the one which was written while the client could not see it.** Either the remote version survives alone, or both survive. What must never happen is the local version quietly winning, because that is a user's edit destroyed without anyone being told.
///
@Suite("Conflicts", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(10)))
struct ConflictTests {
    @Test(arguments: LiveEnvironment.servers)
    func `A file changed on both sides at once does not lose the server's version.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Conflict.simultaneousModification") { room in
            let name = "contested.bin"

            // The file both sides are going to disagree about, materialized so that the local change is an edit of known content rather than a creation.
            let original = try await ServerWorkspace.withFixture(named: name, size: 16 * 1024, seed: 61) { source, fingerprint in
                try await room.server.upload(source, to: "/", force: true)

                return fingerprint
            }

            try await Waiter.waitUntil("\"\(name)\" appears in the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let file = room.localURL(of: name)
            _ = try Materialization.materialize(file)
            #expect(try ContentFactory.fingerprintOfFile(at: file) == original)

            let localContent = ContentFactory.content(size: 16 * 1024, seed: 62)
            let remoteContent = ContentFactory.content(size: 16 * 1024, seed: 63)
            let localFingerprint = ContentFactory.fingerprint(of: localContent)
            let remoteFingerprint = ContentFactory.fingerprint(of: remoteContent)

            try await ServerWorkspace.withSynchronisationBlocked {
                // The client cannot act on either of these while it is blocked, which is what lets them diverge.
                try localContent.write(to: file)

                try await ServerWorkspace.withFixture(named: name, size: 16 * 1024, seed: 63) { source, _ in
                    try await room.server.upload(source, to: "/", force: true)
                }

                // The server took the remote edit, and the client is none the wiser.
                #expect(try await room.remoteFingerprint(of: "/\(name)") == remoteFingerprint)
            }

            // Whatever the client decides, it has to settle on one of three outcomes, and all three end this wait so that the assertion below can say which happened. Waiting only for the good ones would report the bad one as an unexplained timeout.
            try await Waiter.poll("the disagreement settles", timeout: LiveEnvironment.scaled(.seconds(240))) {
                let remote = try await room.remoteChildren()

                // A second item is the system having made a conflict copy.
                guard remote.count == 1 else {
                    return true
                }

                // The client took the server's version, or overwrote it with its own.
                let stored = try await room.remoteFingerprint(of: "/\(name)")
                let onDisk = try? ContentFactory.fingerprintOfFile(at: file)

                return stored == localFingerprint || onDisk == remoteFingerprint
            }

            let remote = try await room.remoteChildren()
            var fingerprints = [String: String]()

            for entry in remote {
                fingerprints[entry.name] = try await room.remoteFingerprint(of: "/\(entry.name)")
            }

            // The property this suite exists for. Anything else is a report of what the client chose, not a failure.
            #expect(fingerprints.values.contains(remoteFingerprint), """
            The version written on the server was replaced by the one written locally while the client was blocked, and nothing was kept of it. \
            The server now holds: \(fingerprints.map { "\($0.key) = \($0.value.prefix(12))" }.sorted().joined(separator: ", ")).
            """)

            // Which of the documented paths the client took is worth having in the output of a run, but it is a description rather than a verdict, so it is printed instead of recorded as an issue.
            if fingerprints.values.contains(localFingerprint), remote.count > 1 {
                print("  note: both versions survived, so the system created a conflict copy. The server holds: \(remote.map(\.name).sorted().joined(separator: ", ")).")
            } else if fingerprints.values.contains(localFingerprint) {
                print("  note: the local version reached the server as the only copy.")
            } else {
                print("  note: the remote version won and the local edit did not reach the server as a separate item.")
            }
        }
    }
}
