// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// A file rewritten in the client, and whether the server ends up with the new bytes.
///
/// The smallest quadrant in the matrix: two cells. Content can only be changed on an item which has content, and it can only be changed locally on one whose bytes are already on disk — macOS materializes a file when it is opened, so "edit a placeholder" is not a distinct case but "materialize, then edit", which is a different cell in a different quadrant.
///
/// Small does not mean uninteresting. This is the path every save in every application takes, and the assertion worth having is not that the bytes arrive but that the item is still the same item afterwards: an update carried to the server as a delete and an upload produces exactly the right content under exactly the right name, having discarded the shares, comments and version history the server kept against the old identity.
///
@Suite("Local content update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct LocalContentUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .local, operation: .contentUpdate), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: bytes written in the client become the bytes on the server, without the item becoming a different item.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `Content written in the client reaches the server without replacing the item.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "LocalContentUpdate.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let name = "edited.bin"
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            // Deliberately a different length as well as different bytes, so that a partial write which kept the old size is not mistaken for an unchanged file.
            let replacement = ContentFactory.content(size: ScenarioWorld.smallFileSize * 2, seed: 91)
            let expected = ContentFactory.fingerprint(of: replacement)

            let started = ContinuousClock.now
            try replacement.write(to: url)

            try await Waiter.poll("the server takes the new content", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try await room.remoteFingerprint(of: subject.remotePath) == expected
            }

            MetricsRecorder.record("client to server content update", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let remote = try await room.remoteChildren(of: subject.parentRemotePath)
            let names = remote.map(\.name).sorted()

            #expect(names.filter { $0 == name }.count == 1, """
            The server holds more than one entry named "\(name)" after the edit. It holds: \(names.joined(separator: ", ")).
            """)

            // The clause this quadrant exists for, and the one no assertion about bytes or names can see. An update carried out as a delete and an upload is correct in every visible respect and has thrown away everything the server kept against the old identity.
            if let entry = remote.first(where: { $0.name == name }) {
                #expect(entry.fileIdentifier == subject.before.fileIdentifier, """
                Rewriting the file in the client replaced it on the server rather than updating it in place: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(entry.fileIdentifier ?? "unknown"). The shares, comments and version history of the original belong to a file which no longer exists.
                """)
            }

            let node = try #require(try LocalNode.at(url), "The file is gone from the client after being written to.")

            #expect(!node.isDataless, "The file this test wrote to became a placeholder, so the bytes it wrote are no longer on the disk they were written to.")
            #expect(node.size == Int64(replacement.count), "The client reports \(node.size) bytes where \(replacement.count) were written.")

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
