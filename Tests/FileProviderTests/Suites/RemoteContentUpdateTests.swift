// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// A file rewritten on the server, and what the client does about it.
///
/// Four cells, and they ask two different questions of the same event.
///
/// Where the client already holds the bytes, a new version on the server has to be reconciled with them, and the file ends up matching what the server now stores.
///
/// Where it does not — a file the user has never opened — the interesting requirement is what must **not** happen. The item's metadata and version have to follow the server while its content stays off the disk. A client which downloads the new bytes has spent a transfer on a file nobody has asked for, and it is the classic regression this axis exists to catch: the model names it explicitly, because an implementation which refreshes an item by fetching it is correct in every respect a test of names, sizes and bytes can see.
///
/// The change is deliberately given a different length as well as different bytes, so that propagation can be observed by looking the item up rather than by reading it — reading it would materialize the very item whose placeholder state is under test.
///
@Suite("Remote content update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct RemoteContentUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .remote, operation: .contentUpdate), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: a new version on the server reaches the client, and reaches a placeholder without materializing it.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `Content changed on the server reaches the client without fetching what it never had.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "RemoteContentUpdate.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let name = "revised.bin"
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            let replacement = ContentFactory.content(size: ScenarioWorld.smallFileSize * 2, seed: 92)
            _ = replacement

            // A package's bytes live in a file inside it. The model puts files and bundles in the same class — a content update is legal on both — and this is where that costs a line.
            let inside = ScenarioWorld.contentComponent(of: cell.item.kind)
            let contentURL = inside.map { url.appending(path: $0, directoryHint: .notDirectory) } ?? url
            let contentRemotePath = inside.map { "\(subject.remotePath)/\($0)" } ?? subject.remotePath

            let started = ContinuousClock.now

            try await ServerWorkspace.withFixture(named: inside ?? name, size: replacement.count, seed: 92) { source, _ in
                try await room.server.upload(source, to: inside == nil ? subject.parentRemotePath : subject.remotePath, force: true)
            }

            // Awaited by size rather than by content, because reading the file is what would materialize it — and for half these cells the thing being tested is that it was not materialized. The new content is a different length from the old on purpose, so that a lookup can see the change.
            try await Waiter.waitUntilBlocking("the client learns the file has changed", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try LocalNode.at(contentURL)?.size == Int64(replacement.count)
            }

            MetricsRecorder.record("server to client content update", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let node = try #require(try LocalNode.at(contentURL), "The file is gone from the client after being changed on the server.")

            switch level {
                case .dataless:
                    // The regression the model names. Refreshing an item by fetching it passes every assertion about names, sizes and bytes, and costs a user a download of a file they have never opened.
                    #expect(node.isDataless, """
                    A content change on the server materialized a file the user had never opened: it was a placeholder before and holds \(node.allocatedBlocks) blocks of content now. Updating metadata and version is all this change required.
                    """)

                case .materialized:
                    // Compared against what the server holds rather than against the bytes the fixture was built from, so the assertion stays true to its name if the fixture ever changes.
                    let arrived = try Data(contentsOf: contentURL)
                    let stored = try await room.remoteFingerprint(of: contentRemotePath)

                    #expect(ContentFactory.fingerprint(of: arrived) == stored, """
                    The file the client had already downloaded still reads as something other than what the server now holds, so the two sides disagree about the contents of a file the user has open.
                    """)

                case .evicted, .materializedDeep, .unknown:
                    throw ScenarioWorldError.unsupported("a cell at \(level.rawValue), which the shared filter excludes")
            }

            // Asserted for both, because a content change must not become a replacement in either direction.
            let remote = try await room.remoteChildren(of: subject.parentRemotePath)

            if let entry = remote.first(where: { $0.name == name }) {
                #expect(entry.fileIdentifier == subject.before.fileIdentifier, """
                The file has a different identity on the server after its content changed: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(entry.fileIdentifier ?? "unknown").
                """)
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
