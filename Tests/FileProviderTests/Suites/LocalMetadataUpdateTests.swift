// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item renamed in the client, and whether the server renames it rather than replacing it.
///
/// The mirror of ``RemoteMetadataUpdateTests``, and the quadrant where the cheapest-looking implementation is the most expensive mistake. A rename carried to the server as a delete and an upload produces a result which is correct by name and correct by content, and which has thrown away the item's identity — and with it every share, favourite, comment and version the server kept against that identity. Only ``ScenarioMatrix/Oracle/identityStability`` sees the difference.
///
/// Six of its twelve cells rename a **placeholder**. Renaming is metadata and needs no content, so a client which fetches the file in order to rename it is spending a download on a change of name — and one of those six is a folder whose contents were never listed, which has to be renamed without being entered.
///
@Suite("Local metadata update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct LocalMetadataUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = ScenarioSelection.cells(of: Quadrant(origin: .local, operation: .metadataUpdate))

    ///
    /// The contract: a name changed in the client becomes that name on the server, and the item stays the same item.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `A name changed in the client becomes that name on the server, and changes nothing else.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "LocalMetadataUpdate.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let before = ScenarioWorld.name("before", for: cell.item.kind, encoding: cell.encoding)
            let after = ScenarioWorld.name("after", for: cell.item.kind, encoding: cell.encoding)

            let subject = try await ScenarioWorld.build(cell, in: room, named: before)
            let oldURL = room.localURL(of: subject.localPath(of: before))
            let newURL = room.localURL(of: subject.localPath(of: after))

            let started = ContinuousClock.now
            try FileManager.default.moveItem(at: oldURL, to: newURL)

            try await Waiter.poll("the server takes the new name", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try await room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == after }
            }

            MetricsRecorder.record("client to server rename", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let remote = try await room.remoteChildren(of: subject.parentRemotePath)
            let names = remote.map(\.name).sorted()

            #expect(!names.contains(before), """
            The server still holds the item under its old name "\(before)" as well as its new one, so the rename left a duplicate behind. It holds: \(names.joined(separator: ", ")).
            """)

            // The clause the quadrant exists for. A rename which destroys the identity is invisible to every assertion about names and bytes.
            if let after = remote.first(where: { $0.name == after }) {
                #expect(after.fileIdentifier == subject.before.fileIdentifier, """
                Renaming the item in the client gave it a new identity on the server rather than renaming it in place: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(after.fileIdentifier ?? "unknown"). The shares, favourites, comments and version history of the original belong to an item which no longer exists.
                """)
            }

            // Renaming is metadata, so a placeholder must still be a placeholder afterwards. A client which downloads a file in order to change its name has spent a transfer on nothing.
            //
            // Against `!= .materialized` rather than `== .dataless`, which is what this said and which inverted the clause for every evicted cell. An evicted item is dataless — that is what eviction does, and the two states are indistinguishable to a test process, same flag and same zero blocks. Comparing against `.dataless` therefore demanded that an evicted file come back *materialized*: a client which renamed it without fetching failed, and a client which downloaded it in order to rename it passed. The one clause this quadrant exists for rewarded the defect it exists to catch.
            if cell.item.kind == .file, let node = try LocalNode.at(newURL) {
                #expect(node.isDataless == (level != .materialized), """
                Renaming the file in the client changed how much of it is on disk: it was \(level.rawValue) and is now \(node.isDataless ? "a placeholder" : "materialized").
                """)
            }

            if let fingerprint = subject.fingerprint {
                #expect(try await room.remoteFingerprint(of: subject.remotePath(of: after)) == fingerprint, "The content of the item changed during a rename, which alters only its name.")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
