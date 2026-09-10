// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// What a server going away and coming back does to work in flight.
///
/// The interesting property is not that synchronisation stops while the server is unreachable — it obviously does — but that nothing is lost and nobody has to intervene once it returns. A client which forgets a local change made during an outage loses the user's work silently, which is the worst failure this suite can look for.
///
/// The outage is produced by suspending the container rather than stopping it: these containers remove themselves when they stop, and a removed server is not the same experiment.
///
@Suite("Recovery", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(10)))
struct RecoveryTests {
    @Test(arguments: LiveEnvironment.servers)
    func `A change made while the server is unreachable reaches it afterwards.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Recovery.writeDuringOutage") { room in
            let name = "written-in-the-dark.bin"
            let content = ContentFactory.content(size: 32 * 1024, seed: 51)

            try await ServerWorkspace.withServerPaused(underTest) {
                try content.write(to: room.localURL(of: name))

                // A local write does not depend on the server, which is the entire promise of a local file.
                #expect(LocalDirectory.exists(room.localURL(of: name)))
            }

            let entry = try await room.waitForRemoteEntry(named: name, timeout: LiveEnvironment.scaled(.seconds(180)))
            #expect(entry.size == Int64(content.count))
            #expect(try await room.remoteFingerprint(of: "/\(name)") == ContentFactory.fingerprint(of: content))
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Content already on disk stays readable while the server is unreachable.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Recovery.readDuringOutage") { room in
            let name = "already-here.bin"

            let fingerprint = try await ServerWorkspace.withFixture(named: name, size: 64 * 1024, seed: 52) { source, fingerprint in
                try await room.server.upload(source, to: "/", force: true)

                return fingerprint
            }

            try await Waiter.waitUntil("\"\(name)\" appears in the domain", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let file = room.localURL(of: name)
            _ = try Materialization.materialize(file)

            try await ServerWorkspace.withServerPaused(underTest) {
                // Nothing here needs the server: the content is on disk and the directory has been enumerated once already.
                let digest = try ContentFactory.fingerprintOfFile(at: file)
                let names = try room.localChildren().map(\.name)

                #expect(digest == fingerprint)
                #expect(names.contains(name))
                #expect(LocalNode.at(file)?.isDataless == false)
            }
        }
    }
}
