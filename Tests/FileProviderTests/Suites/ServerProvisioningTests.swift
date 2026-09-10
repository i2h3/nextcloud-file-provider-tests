// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Rainmaker
import ServerHarness
import Testing

///
/// The server side of the harness does what the rest of the suite assumes it does.
///
/// None of this involves the desktop client. It is the part which can be trusted only if it is checked: every File Provider test rests on a user which exists, authenticates with an app password, and starts with a genuinely empty files root, and a failure in any of those would otherwise be reported as a synchronisation bug.
///
@Suite("Server provisioning", .requiresLiveEnvironment, .serialized)
struct ServerProvisioningTests {
    @Test(arguments: LiveEnvironment.servers)
    func `The deployed server answers and reports its capabilities.`(_ underTest: ServerUnderTest) async throws {
        let capabilities = try await Server(address: underTest.serverAddress, password: underTest.adminPassword, user: underTest.adminUser).capabilities()

        #expect(capabilities.version.major > 0)
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A freshly provisioned user starts with an empty files root.`(_ underTest: ServerUnderTest) async throws {
        try await ServerWorkspace.with(underTest, testName: "ServerProvisioning.userStartsEmpty") { workspace in
            let entries = try await RemoteListing.children(of: "/", on: workspace.server)

            #expect(entries.isEmpty, "A new user should own nothing, but the server reports: \(entries.map(\.name).joined(separator: ", ")). Check that the skeleton directory is switched off on this release.")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `The issued app password authenticates as the user it was issued for.`(_ underTest: ServerUnderTest) async throws {
        try await ServerWorkspace.with(underTest, testName: "ServerProvisioning.appPasswordAuthenticates") { workspace in
            let root = try await workspace.server.info("/")

            #expect(root.isDirectory)
            #expect(workspace.user.appPassword != workspace.user.password, "The app password should be issued by the server rather than being the account password.")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Content survives an upload and a download unchanged.`(_ underTest: ServerUnderTest) async throws {
        try await ServerWorkspace.with(underTest, testName: "ServerProvisioning.contentSurvivesRoundTrip") { workspace in
            try await ServerWorkspace.withFixture(named: "round-trip.bin", size: 128 * 1024, seed: 42) { source, fingerprint in
                try await workspace.server.upload(source, to: "/", force: true)

                // Rainmaker takes the destination directory here, just as it does for an upload, and keeps the item's own name.
                let destination = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

                defer {
                    try? FileManager.default.removeItem(at: destination)
                }

                try await workspace.server.download("/round-trip.bin", to: destination, force: true)

                #expect(try ContentFactory.fingerprintOfFile(at: destination.appending(path: "round-trip.bin", directoryHint: .notDirectory)) == fingerprint)
            }
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A directory and its contents are listed as they were created.`(_ underTest: ServerUnderTest) async throws {
        try await ServerWorkspace.with(underTest, testName: "ServerProvisioning.listsWhatWasCreated") { workspace in
            try await workspace.server.createDirectory("/folder")

            try await ServerWorkspace.withFixture(named: "nested.bin", size: 2048, seed: 7) { source, _ in
                try await workspace.server.upload(source, to: "/folder", force: true)
            }

            let root = try await RemoteListing.children(of: "/", on: workspace.server)
            #expect(root.map(\.name) == ["folder"])
            #expect(root.first?.isDirectory == true)

            let nested = try await RemoteListing.children(of: "/folder", on: workspace.server)
            #expect(nested.map(\.name) == ["nested.bin"])
            #expect(nested.first?.size == 2048)
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A deleted file lands in the trash and can be restored.`(_ underTest: ServerUnderTest) async throws {
        try await ServerWorkspace.with(underTest, testName: "ServerProvisioning.deletionIsRecoverable") { workspace in
            try await ServerWorkspace.withFixture(named: "doomed.bin", size: 512, seed: 13) { source, _ in
                try await workspace.server.upload(source, to: "/", force: true)
            }

            try await workspace.server.delete("/doomed.bin")
            #expect(try await RemoteListing.children(of: "/", on: workspace.server).isEmpty)

            let trashed = try await workspace.server.trash()
            let item = try #require(trashed.first { $0.name == "doomed.bin" })

            try await workspace.server.restore(item)
            #expect(try await RemoteListing.children(of: "/", on: workspace.server).map(\.name) == ["doomed.bin"])
        }
    }
}
