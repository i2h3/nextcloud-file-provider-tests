// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// The same item deleted on both sides at once.
///
/// The first generated quadrant whose origin is ``ScenarioMatrix/Origin/concurrent``, and the gentlest of the three, because its two branches agree. Whichever side is seen first, the end state both sides are asking for is the same one — the item is gone — so the contract stays determined where it matters and the race decides only how the system gets there.
///
/// That is exactly why it is worth having first. A delete-delete which ends with the item gone from both sides is unremarkable; one which ends with the item restored, or duplicated in the trash, or gone locally while still on the server, is a failure that no single-sided quadrant can produce. The two deletions are issued without pausing the item, because the contract the model assigns to a concurrent cell is the **unpaused** one: pausing it to force a cleaner divergence would establish a different cell than the one being claimed.
///
/// The one clause this cannot judge is the one the quadrant is named for. ``ScenarioMatrix/Oracle/conflictResolution`` permits `conflictCopy`, `serverWon` or `localWon`, and those name which branch's **content** survived. A delete on both sides leaves no content to attribute to a winner: the only member that would be visible is a conflict copy, and its absence says nothing about which of the other two happened. It is declined rather than guessed.
///
@Suite("Concurrent delete", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct ConcurrentDeleteTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .concurrent, operation: .delete), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: when both sides delete the same item, it ends up gone from both and recoverable from the trash.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item deleted on both sides at once ends up gone from both, and not lost from the trash.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "ConcurrentDelete.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let name = ScenarioWorld.name("contested", for: cell.item.kind)
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            let started = ContinuousClock.now

            // Issued together rather than one after the other. `async let` starts the server's deletion immediately, and the local one runs while it is in flight — which is as close to simultaneous as a test process can arrange without pausing the item, and pausing it would establish a different cell.
            async let serverDeletion: Void = room.server.delete(subject.remotePath)

            try FileManager.default.removeItem(at: url)

            // A refusal here is an outcome rather than an error: if the client's deletion arrived first, the server has nothing left to delete, and that is one of the ways this race legitimately resolves.
            let serverAcceptedDeletion: Bool

            do {
                try await serverDeletion
                serverAcceptedDeletion = true
            } catch {
                serverAcceptedDeletion = false
            }

            #expect(try LocalNode.at(url) == nil, """
            Removing the item in the client left it in place, so nothing below this says anything about what the two deletions did to each other.
            """)

            var reachedServer = true

            do {
                try await Waiter.poll("the server lets go of \"\(name)\"", timeout: LiveEnvironment.scaled(.seconds(180))) {
                    try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == name }
                }
            } catch is WaitTimeoutError {
                reachedServer = false
            }

            // Read before the message needs it, rather than inside it: whether the item came back is a second observation, and one worth making after time has passed rather than at the moment of deletion.
            let survivedLocally = try LocalNode.at(url) != nil

            #expect(reachedServer, """
            Both sides deleted "\(name)" and the server still holds it. The server \(serverAcceptedDeletion ? "accepted its own deletion, so something put the item back" : "refused its own deletion, which means the client's deletion had already arrived — and then the item survived both"). The item is \(survivedLocally ? "back in the client, so the deletion was reverted" : "gone from the client, so the two sides disagree permanently").
            """)

            guard reachedServer else {
                return
            }

            MetricsRecorder.record("concurrent deletion", duration: ContinuousClock.now - started, in: room, test: cell.description)

            // The invariant which holds across every way this race can resolve: a deletion both sides asked for must still be recoverable. How many copies reach the trash is not asserted — one side's deletion arriving after the other's has already been recorded is a legal way to end up with two, and a test which demanded one would be asserting an implementation detail.
            // With the trash disabled the API gives no contract for where a deleted item goes — the system decides, and the destination is explicitly not guaranteed. So where it went is recorded rather than asserted; what must hold either way is that it is gone from the domain, which is checked above.
            guard cell.trash == .with else {
                let remains = (try? await room.server.trash()) ?? []

                UnderdeterminedOutcome.observed(remains.contains { $0.name == name } ? "providerDefinedDestination" : "removedPermanently", for: .trashPlacement, in: cell)

                ScenarioOracle.decline("conflictResolution", because: ScenarioOracle.mutualDeletionReason)
                ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
                ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
                ScenarioOracle.decline("realizationState", because: ScenarioOracle.deletedItemReason)

                return
            }

            let trashed = try await room.server.trash()
            let copies = trashed.filter { $0.name == name }

            #expect(!copies.isEmpty, """
            The item was deleted on both sides and reached the server's trash from neither, so a user who deletes a file twice cannot get it back. The trash holds: \(trashed.map(\.name).sorted().joined(separator: ", ")).
            """)

            if copies.count > 1 {
                print("  note: both deletions were recorded separately — the trash holds \(copies.count) copies of \"\(name)\".")
            }

            ScenarioOracle.decline("conflictResolution", because: ScenarioOracle.mutualDeletionReason)
            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.deletedItemReason)
        }
    }
}
