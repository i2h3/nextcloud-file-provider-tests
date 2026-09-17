// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item moved between directories on the server, and whether the client follows it.
///
/// The mirror of ``LocalMoveTests``, and the harder direction. A move made in the client is one `rename` the system hands to the provider as a single change; a move made on the server arrives as a difference between two enumerations, and the client has to recognise that an item which vanished from one container and appeared in another is the same item rather than a deletion followed by a creation.
///
/// Getting that wrong is invisible to every assertion about names and content. The file is in the right place with the right bytes, and its identity — with the shares, favourites, comments and version history hanging from it — belongs to something that no longer exists. ``ScenarioMatrix/Oracle/moveIdentity`` is the only clause that sees it, and this quadrant is where it matters most, because reconstructing an identity across containers is exactly what a client is most likely to skip.
///
/// ## What the cells pin
///
/// As in ``LocalMoveTests``, the realization describes the two **containers** rather than the item. Half of these cells require a container the client has never listed — either the one the item leaves or the one it arrives in — which is the interesting half: a client which only notices changes in folders it has already enumerated would pass every materialized cell and fail these, and a user would find that a file moved on the web never arrives in a folder they had not opened.
///
@Suite("Remote move", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct RemoteMoveTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .remote, operation: .move), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item moved on the server moves in the client, and stays the same item.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item moved between directories on the server moves in the client and stays the same item.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .parents(source, destination) = cell.realization else {
            throw ScenarioWorldError.unsupported("a move whose realization does not describe its two containers")
        }

        try await CleanRoom.with(underTest, testName: "RemoteMove.\(cell.item.kind.rawValue).\(source.rawValue)-\(destination.rawValue)") { room in
            let name = ScenarioWorld.name("travelling", for: cell.item.kind)
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)

            guard let destinationLocal = subject.destinationLocal else {
                throw ScenarioWorldError.unsupported("a move with no destination, which the world builder should have refused")
            }

            guard let destinationRemote = subject.destinationPath else {
                throw ScenarioWorldError.unsupported("a move with no destination on the server, which the world builder should have refused")
            }

            let from = room.localURL(of: subject.localPath(of: name))
            let to = room.localURL(of: destinationLocal)

            let started = ContinuousClock.now
            try await room.server.move(subject.remotePath, to: destinationRemote, overwrite: false)

            // Both paths, and by lookup rather than by listing. Half of these cells forbid entering one of the two containers, so the arrival cannot be observed by enumerating the place it arrives in — and watching only the destination would pass while a copy was left behind at the source.
            try await Waiter.waitUntilBlocking("the move reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try LocalNode.at(to) != nil && LocalNode.at(from) == nil
            }

            MetricsRecorder.record("server to client move", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let arrived = try #require(try LocalNode.at(to), "The item vanished between the wait and the reading of it.")

            #expect(arrived.kind == (cell.item.kind == .file ? .file : .directory), "The item arrived at its destination as the wrong sort of thing.")

            // The server is asked as well, because the two halves fail differently: a client which did not follow the move leaves the item at its old path, while a server which did not perform it never had the item at the new one.
            let remote = try await room.remoteChildren(of: subject.destinationRemotePath ?? "/")

            #expect(remote.contains { $0.name == name }, """
            The server does not hold the item where it was moved to, so this run measured a move which never happened rather than a client which did not follow one.
            """)

            // The clause this quadrant exists for, and the one no assertion about names or bytes can stand in for.
            if let after = remote.first(where: { $0.name == name }) {
                #expect(after.fileIdentifier == subject.before.fileIdentifier, """
                The item crossed containers on the server and came back with a new identity: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(after.fileIdentifier ?? "unknown"). Whatever the server kept against the old identity — shares, favourites, comments, versions — now belongs to an item which no longer exists.
                """)
            }

            if let fingerprint = subject.fingerprint {
                #expect(try await room.remoteFingerprint(of: destinationRemote) == fingerprint, "The content of the item changed during a move, which alters only where it is.")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.movedItemReason)
        }
    }
}
