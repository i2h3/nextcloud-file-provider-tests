// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RoomManifest``.
///
/// A clean room's directory is named after the Nextcloud user it created, and that name is derived from a short label which has nothing to do with the name of the test function. Without this record a failure cannot be connected to the only logs which could explain it, so what is pinned here is the connection it carries: the identity, the user, the server, and the window a failure is placed by when the identity is missing. Placing a moment in that window is ``RunEvidenceTests``.
///
@Suite("Room manifest")
struct RoomManifestTests {
    ///
    /// A server for a room to have run against.
    ///
    static let server = RunManifestServer(ServerUnderTest(
        tag: "latest",
        serverAddress: URL(string: "http://localhost:51658")!,
        containerIdentifier: "c0ffee",
        adminUser: "admin",
        adminPassword: "secret",
        isPushEnabled: false,
        versionString: "34.0.3"
    ))

    ///
    /// A room which began an hour ago and lasted a minute.
    ///
    /// - Returns: The manifest.
    ///
    static func makeManifest() -> RoomManifest {
        var manifest = RoomManifest(
            testName: "Conflict.simultaneousModification",
            testIdentifier: "FileProviderTests.ConflictTests/theTest(_:)",
            testDisplayName: "A file changed on both sides at once does not lose the server's version.",
            user: "conflict.simultaneousmodification-ee2ce462-001",
            server: server,
            startedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        manifest.endedAt = Date(timeIntervalSince1970: 1_000_060)

        return manifest
    }

    @Test
    func `A manifest survives being written and read back.`() throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try Self.makeManifest().write(into: directory)
        let read = try #require(RoomManifest.read(from: directory))

        #expect(read.testName == "Conflict.simultaneousModification")
        #expect(read.testDisplayName == "A file changed on both sides at once does not lose the server's version.")
        #expect(read.user == "conflict.simultaneousmodification-ee2ce462-001")
        #expect(read.server.versionString == "34.0.3")
    }

    ///
    /// The identity comes from the testing library and may be absent. The window may not, which is why attribution rests on it — see ``RunEvidenceTests`` for the rule which reads it.
    ///
    @Test
    func `A manifest without a test identity is still usable.`() throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest = RoomManifest(testName: "Some.test", user: "some.test-0001", server: Self.server)
        try manifest.write(into: directory)

        let read = try #require(RoomManifest.read(from: directory))
        #expect(read.testIdentifier == nil)
        #expect(read.testDisplayName == nil)
    }

    @Test
    func `A directory without a manifest reads as none rather than failing.`() {
        #expect(RoomManifest.read(from: URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)) == nil)
    }
}
