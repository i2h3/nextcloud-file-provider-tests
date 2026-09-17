// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item moved between directories in the client.
///
/// The first suite in this project to move anything between containers at all. Every rename tested until now, in either direction, kept the item where it was — so a move has been an untested operation, and the difference is not cosmetic: a move spans two containers, and the client has to apply it as one change to an item rather than as a removal from one place and a creation in another.
///
/// ## Why this quadrant is shaped differently from the others
///
/// A move is the one operation whose cell pins the state of the **containers** rather than of the item. ``ScenarioMatrix/Realization/parents(source:destination:)`` carries a level for each end, and the item's own realization is left unconstrained, because what is interesting is whether the client can move something out of a folder it has never listed, or into one.
///
/// That makes half of these cells depend on something nobody has measured: that looking an item up by path inside a container which was never enumerated does not quietly enumerate it. If it does, the cell would establish a materialized container while claiming a dataless one, and pass. ``ScenarioWorld`` therefore asserts the enumeration ledger immediately after the wait, so the assumption fails loudly here rather than silently everywhere.
///
@Suite("Local move", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct LocalMoveTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .local, operation: .move), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item moved in the client moves on the server, and stays the same item.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item moved between directories in the client moves on the server and stays the same item.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .parents(source, destination) = cell.realization else {
            throw ScenarioWorldError.unsupported("a move whose realization does not describe its two containers")
        }

        try await CleanRoom.with(underTest, testName: "LocalMove.\(cell.item.kind.rawValue).\(source.rawValue)-\(destination.rawValue)", cell: cell.description) { room in
            let name = ScenarioWorld.name("travelling", for: cell.item.kind)
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)

            let from = room.localURL(of: subject.localPath(of: name))

            guard let destinationLocal = subject.destinationLocal, let destinationRemote = subject.destinationPath else {
                throw ScenarioWorldError.unsupported("a move with no destination, which the world builder should have refused")
            }

            let to = room.localURL(of: destinationLocal)

            let started = ContinuousClock.now
            try FileManager.default.moveItem(at: from, to: to)

            try await Waiter.poll("the item arrives at its destination on the server", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try await room.remoteChildren(of: subject.destinationRemotePath ?? "/").contains { $0.name == name }
            }

            MetricsRecorder.record("client to server move", duration: ContinuousClock.now - started, in: room, test: cell.description)

            // Gone from where it was, which is what separates a move from a copy. A client which uploads to the destination and leaves the source alone produces two items where the user has one.
            let left = try await room.remoteChildren(of: subject.parentRemotePath).map(\.name).sorted()

            #expect(!left.contains(name), """
            The server still holds the item where it was as well as where it went, so the move was applied as a copy. Its old container holds: \(left.joined(separator: ", ")).
            """)

            #expect(try LocalNode.at(from) == nil, "The item is still at its old path in the client after being moved.")

            // The clause this quadrant carries that the rename quadrants do not: an identity has to survive crossing a container boundary, not merely a change of name.
            let arrived = try await room.remoteChildren(of: subject.destinationRemotePath ?? "/").first { $0.name == name }

            #expect(arrived?.fileIdentifier == subject.before.fileIdentifier, """
            Moving the item gave it a new identity on the server rather than moving it: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(arrived?.fileIdentifier ?? "unknown"). Everything the server kept against the old identity — shares, favourites, comments, versions — belongs to an item which no longer exists.
            """)

            if let fingerprint = subject.fingerprint {
                #expect(try await room.remoteFingerprint(of: destinationRemote) == fingerprint, "The content of the item changed during a move, which alters only where it is.")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)

            ScenarioOracle.decline("realizationState", because: ScenarioOracle.movedItemReason)
        }
    }
}
