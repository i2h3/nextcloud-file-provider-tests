// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// What the server has shows up in the client, and its content arrives intact when it is asked for.
///
/// The two halves are deliberately separate assertions. An item appearing is enumeration; its content arriving is materialization. Conflating them hides which of the two broke.
///
@Suite("Server to client", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(5)))
struct ServerToClientTests {
    @Test(arguments: LiveEnvironment.servers)
    func `A file created on the server appears in the client as a placeholder and materializes on demand.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ServerToClient.fileAppearsAndMaterializes") { room in
            let name = "appears.bin"
            let content = ContentFactory.content(size: 64 * 1024, seed: 1)
            let fingerprint = ContentFactory.fingerprint(of: content)
            let file = room.localURL(of: name)
            let started = ContinuousClock.now

            try await ServerWorkspace.withFixture(named: name, size: 64 * 1024, seed: 1) { source, _ in
                try await room.server.upload(source, to: "/", force: true)
            }

            do {
                try await Waiter.waitUntil("\"\(name)\" appears in the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                    try room.localChildren().contains { $0.name == name }
                }
            } catch {
                try await room.collectDiagnostics(reason: String(describing: error), focus: file)

                throw error
            }

            MetricsRecorder.record("server to client propagation", duration: ContinuousClock.now - started, in: room, test: "ServerToClient.fileAppearsAndMaterializes", payloadSize: Int64(content.count))

            let placeholder = try #require(LocalNode.at(file))
            #expect(placeholder.size == Int64(content.count))
            #expect(placeholder.isDataless, "The file should arrive as a placeholder rather than already materialized.")

            let materializationStarted = ContinuousClock.now
            let arrived = try Materialization.materialize(file)
            MetricsRecorder.record("materialization", duration: ContinuousClock.now - materializationStarted, in: room, test: "ServerToClient.fileAppearsAndMaterializes", payloadSize: Int64(content.count))

            #expect(ContentFactory.fingerprint(of: arrived) == fingerprint)
            #expect(LocalNode.at(file)?.isDataless == false)
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A directory created on the server appears with its contents once it is entered.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "ServerToClient.directoryAppears") { room in
            try await room.server.createDirectory("/folder")

            try await ServerWorkspace.withFixture(named: "nested.bin", size: 1024, seed: 2) { source, _ in
                try await room.server.upload(source, to: "/folder", force: true)
            }

            try await Waiter.waitUntil("\"folder\" appears in the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == "folder" && $0.kind == .directory }
            }

            // Entering the directory is a separate, deliberate act: the first read of a container is what drives its enumerator.
            try await Waiter.waitUntil("\"nested.bin\" appears inside \"folder\"", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren(of: "folder").contains { $0.name == "nested.bin" }
            }

            let remote = try await RemoteListing.children(of: "/folder", on: room.server)
            let local = try room.localChildren(of: "folder")
            let differences = ConvergenceCheck.compare(remote: remote, local: local)

            #expect(differences.isEmpty, "The server and the client disagree: \(differences.map(\.description).joined(separator: " "))")
        }
    }
}
