// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RoomManifest``.
///
/// A clean room's directory is named after the Nextcloud user it created, and that name is derived from a short label which has nothing to do with the name of the test function. Without this record a failure cannot be connected to the only logs which could explain it, so what is pinned here is the connection: the identity it carries, and the window by which a failure is placed in a room even when the identity is missing.
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
    /// This is what attributes a failure to a server. Rooms never overlap, so the room whose window holds the moment a test failed is the room that test ran in — which is how the argument is recovered without the testing library naming it.
    ///
    @Test
    func `A moment inside the room's life is recognised as belonging to it.`() {
        let manifest = Self.makeManifest()

        #expect(manifest.contains(Date(timeIntervalSince1970: 1_000_030)))
        #expect(manifest.contains(Date(timeIntervalSince1970: 1_000_000)))
        #expect(manifest.contains(Date(timeIntervalSince1970: 1_000_060)))
    }

    @Test
    func `A moment outside the room's life is not.`() {
        let manifest = Self.makeManifest()

        #expect(!manifest.contains(Date(timeIntervalSince1970: 999_999)))
        #expect(!manifest.contains(Date(timeIntervalSince1970: 1_000_061)))
    }

    ///
    /// A room whose teardown never finished is exactly the case where something went wrong inside it, so it stays open rather than swallowing every later moment or none.
    ///
    @Test
    func `A room which never recorded its end stays open.`() {
        var manifest = Self.makeManifest()
        manifest.endedAt = nil

        #expect(manifest.contains(Date(timeIntervalSince1970: 2_000_000)))
        #expect(!manifest.contains(Date(timeIntervalSince1970: 999_999)))
    }

    ///
    /// The identity comes from the testing library and may be absent. The window may not, which is why attribution rests on it.
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
        #expect(read.contains(read.startedAt))
    }

    @Test
    func `A directory without a manifest reads as none rather than failing.`() {
        #expect(RoomManifest.read(from: URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)) == nil)
    }
}
