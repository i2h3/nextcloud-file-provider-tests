// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// Names survive the trip in both directions, including the ones two systems spell differently.
///
/// This is the group with the longest history of quiet data loss in synchronisation clients, and the reason is that macOS and a Nextcloud server do not agree on what a file name is. A client which compares the two spellings by their bytes concludes that a file is missing and either uploads it again or deletes it.
///
/// What the client actually does is consistent, and these tests pin it down: the wire format is precomposed and the local file system hands out decomposed, so a name written decomposed is stored precomposed and read back decomposed. Both halves are asserted, in both directions, along with the item existing exactly once on each side.
///
@Suite("Naming", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(10)))
struct NamingTests {
    ///
    /// Names which are awkward for one of the two sides, with the reason each one is in the list.
    ///
    static let names = [
        "Übung.txt", // Precomposed, which is how a server stores it and how macOS does not hand it back.
        "e\u{0301}clair.txt", // Decomposed at the source, so the server receives what macOS produces.
        "🌧️ rain.txt", // Outside the basic multilingual plane, and with a variation selector.
        "ohne-endung", // No extension, which some implementations treat as a directory.
        "sehr " + String(repeating: "langer", count: 30) + ".txt", // Long, but inside the 255 byte limit of a path component.
    ]

    @Test(arguments: LiveEnvironment.servers, names)
    func `A name survives the trip from the server into the client.`(_ underTest: ServerUnderTest, _ name: String) async throws {
        try await CleanRoom.with(underTest, testName: "Naming.fromServer") { room in
            let fingerprint = try await ServerWorkspace.withFixture(named: name, size: 4096, seed: 41) { source, fingerprint in
                try await room.server.upload(source, to: "/", force: true)

                return fingerprint
            }

            let remote = try await room.remoteChildren()
            #expect(remote.count == 1, "The server should hold exactly the uploaded file.")

            let remoteName = try #require(remote.first?.name)

            try await Waiter.waitUntil("the client holds one item", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { !LocalDirectory.systemEntryNames.contains($0.name) }
            }

            let local = try room.localChildren().filter { !LocalDirectory.systemEntryNames.contains($0.name) }
            #expect(local.count == 1, "The client should hold exactly one item but holds: \(local.map(\.name).joined(separator: ", "))")

            // A difference in normalization is expected here and asserted on its own terms below. Every other kind of disagreement is a failure.
            for difference in ConvergenceCheck.compare(remote: remote, local: local) {
                guard case .nameNormalizationDiffers = difference else {
                    Issue.record("\(difference)")

                    continue
                }
            }

            let arrived = try #require(local.first)

            // Canonical equivalence is the invariant which matters: whatever the two sides spell, they have to mean the same name, or the client is looking at a file it will conclude is missing. Swift compares strings canonically, so this is the question being asked.
            #expect(arrived.name == remoteName, "The client spells the name as \(Array(arrived.name.unicodeScalars)), which is not the same name as the server's \(Array(remoteName.unicodeScalars)).")

            #expect(Data(arrived.name.utf8) == Data(remoteName.decomposedStringWithCanonicalMapping.utf8), "The file system is expected to hand out the decomposed spelling of \(Array(remoteName.unicodeScalars)), but handed out \(Array(arrived.name.unicodeScalars)).")

            #expect(try ContentFactory.fingerprintOfFile(at: arrived.url) == fingerprint)

            // The failure this whole suite exists for: having enumerated a decomposed name locally and holding a precomposed one on the server, a client which compares the two by their bytes concludes the file is missing and uploads it a second time. That only becomes visible once the local side has been enumerated, which is why the server is asked again here rather than only before.
            let afterEnumeration = try await room.remoteChildren()
            #expect(afterEnumeration.count == 1, "Enumerating the name locally made the server hold: \(afterEnumeration.map(\.name).joined(separator: ", ")).")
        }
    }

    @Test(arguments: LiveEnvironment.servers, names)
    func `A name survives the trip from the client to the server.`(_ underTest: ServerUnderTest, _ name: String) async throws {
        try await CleanRoom.with(underTest, testName: "Naming.fromClient") { room in
            let content = ContentFactory.content(size: 4096, seed: 42)
            try content.write(to: room.localURL(of: name))

            try await Waiter.poll("the server holds one item", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try await room.remoteChildren().count == 1
            }

            let remote = try #require(try await room.remoteChildren().first)
            #expect(remote.size == Int64(content.count))

            // The server's spelling may differ from the one which was written, so the file is fetched by the name the server itself reports.
            #expect(try await room.remoteFingerprint(of: "/\(remote.name)") == ContentFactory.fingerprint(of: content))

            #expect(remote.name == name, "The server spells the name as \(Array(remote.name.unicodeScalars)), which is not the same name as the \(Array(name.unicodeScalars)) which was written.")

            // The precomposed spelling is what belongs on the wire, and this is the direction where getting it wrong is expensive: a decomposed name stored on the server is handed to every other client of that account, and a Windows or Linux client has no reason to consider it the same file.
            #expect(Data(remote.name.utf8) == Data(name.precomposedStringWithCanonicalMapping.utf8), "The client is expected to upload the precomposed spelling of \(Array(name.unicodeScalars)), but the server stored \(Array(remote.name.unicodeScalars)).")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Renaming only the case of a name reaches the server.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Naming.caseOnlyRename") { room in
            // The volume is case insensitive and the server is not, so this rename is a no-op locally and a real rename remotely.
            let content = ContentFactory.content(size: 2048, seed: 43)
            try content.write(to: room.localURL(of: "casing.txt"))
            try await room.waitForRemoteEntry(named: "casing.txt")

            try FileManager.default.moveItem(at: room.localURL(of: "casing.txt"), to: room.localURL(of: "CASING.TXT"))

            try await Waiter.poll("the server reports the new casing", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try await room.remoteChildren().contains { $0.name == "CASING.TXT" }
            }

            let remote = try await room.remoteChildren()
            #expect(remote.count == 1, "The rename should not have produced a second file: \(remote.map(\.name).joined(separator: ", "))")
            #expect(try await room.remoteFingerprint(of: "/CASING.TXT") == ContentFactory.fingerprint(of: content))
        }
    }
}
