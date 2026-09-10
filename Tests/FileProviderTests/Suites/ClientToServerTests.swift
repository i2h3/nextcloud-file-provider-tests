// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Rainmaker
import ServerHarness
import Testing

///
/// What happens in the client reaches the server, unchanged.
///
/// The interesting cases are not the plain ones. Applications rarely write a file by opening it and writing to it: they write a temporary file and put it in place, which reaches the File Provider as a create followed by a replace, and that is where implementations tend to lose content or produce spurious conflicts.
///
@Suite("Client to server", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(5)))
struct ClientToServerTests {
    @Test(arguments: LiveEnvironment.servers)
    func `A file created in the client appears on the server with the same content.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ClientToServer.fileAppears") { room in
            let name = "created-locally.bin"
            let content = ContentFactory.content(size: 64 * 1024, seed: 21)
            let started = ContinuousClock.now

            try content.write(to: room.localURL(of: name))

            let entry = try await room.waitForRemoteEntry(named: name)
            MetricsRecorder.record("client to server propagation", duration: ContinuousClock.now - started, in: room, test: "ClientToServer.fileAppears", payloadSize: Int64(content.count))

            #expect(entry.size == Int64(content.count))
            #expect(try await room.remoteFingerprint(of: "/\(name)") == ContentFactory.fingerprint(of: content))
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A file written the way applications write it arrives intact.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ClientToServer.atomicSave") { room in
            let name = "document.bin"
            let first = ContentFactory.content(size: 32 * 1024, seed: 22)
            let second = ContentFactory.content(size: 48 * 1024, seed: 23)

            try first.write(to: room.localURL(of: name))
            try await room.waitForRemoteEntry(named: name)

            // This is what a coordinated, atomic save looks like from the file system's side: the new content is written somewhere else and then swapped into place, so the item the provider sees replaced is not the item it saw written.
            let replacement = room.localURL(of: "\(name).replacement")
            try second.write(to: replacement)
            _ = try FileManager.default.replaceItemAt(room.localURL(of: name), withItemAt: replacement)

            try await Waiter.poll("the server has the replaced content", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try await room.remoteChildren().first { $0.name == name }?.size == Int64(second.count)
            }

            #expect(try await room.remoteFingerprint(of: "/\(name)") == ContentFactory.fingerprint(of: second))

            // The replacement file exists in the client for a moment and may well reach the server before it is consumed, so its disappearance is awaited rather than asserted outright.
            var leftovers = [String]()

            try? await Waiter.poll("the server holds nothing but the saved document", timeout: LiveEnvironment.scaled(.seconds(60))) {
                leftovers = try await room.remoteChildren().map(\.name).filter { $0 != name }

                return leftovers.isEmpty
            }

            #expect(leftovers.isEmpty, "The save left something behind on the server: \(leftovers.joined(separator: ", "))")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Renaming in the client renames on the server.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ClientToServer.rename") { room in
            let content = ContentFactory.content(size: 4096, seed: 24)
            try content.write(to: room.localURL(of: "before.bin"))
            try await room.waitForRemoteEntry(named: "before.bin")

            try FileManager.default.moveItem(at: room.localURL(of: "before.bin"), to: room.localURL(of: "after.bin"))

            try await room.waitForRemoteEntry(named: "after.bin")
            try await room.waitForRemoteRemoval(of: "before.bin")

            #expect(try await room.remoteFingerprint(of: "/after.bin") == ContentFactory.fingerprint(of: content))
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A directory created in the client appears with its contents.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ClientToServer.directory") { room in
            let content = ContentFactory.content(size: 2048, seed: 25)
            try FileManager.default.createDirectory(at: room.localURL(of: "folder"), withIntermediateDirectories: true)
            try content.write(to: room.localURL(of: "folder/inside.bin"))

            try await room.waitForRemoteEntry(named: "folder")
            try await room.waitForRemoteEntry(named: "inside.bin", in: "/folder")

            #expect(try await room.remoteFingerprint(of: "/folder/inside.bin") == ContentFactory.fingerprint(of: content))
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Deleting in the client deletes on the server and fills the trash.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ClientToServer.delete") { room in
            let name = "doomed.bin"
            try ContentFactory.content(size: 1024, seed: 26).write(to: room.localURL(of: name))
            try await room.waitForRemoteEntry(named: name)

            try FileManager.default.removeItem(at: room.localURL(of: name))

            try await room.waitForRemoteRemoval(of: name)

            try await Waiter.poll("the server has it in the trash", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try await room.server.trash().contains { $0.name == name }
            }
        }
    }
}
