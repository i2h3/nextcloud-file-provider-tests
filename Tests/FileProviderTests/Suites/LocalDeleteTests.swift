// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item deleted in the client, and whether the server lets go of it.
///
/// The mirror of ``RemoteDeleteTests`` and the first generated quadrant in the client-to-server direction. Six of its twelve cells delete a **placeholder** — an item whose content was never downloaded — which is a case nothing in this project has ever exercised: every deletion in the hand-written suites removes a file the test itself wrote, and a file the test wrote is materialized from birth.
///
/// That case is worth having on its own terms. Deleting a placeholder is the ordinary thing a user does in the Finder with a file they have never opened, and the client has to turn it into a deletion on the server without fetching the content first. Fetching it would be a download nobody asked for, of a file about to cease existing.
///
@Suite("Local delete", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct LocalDeleteTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .local, operation: .delete), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item deleted in the client disappears from the server and is recoverable from its trash.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item deleted in the client disappears from the server and lands in the trash.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "LocalDelete.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let name = ScenarioWorld.name("doomed", for: cell.item.kind)
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            let started = ContinuousClock.now
            try FileManager.default.removeItem(at: url)

            // Asserted here rather than after the wait, and the ordering is the whole point. A deletion which never reached the server has two completely different explanations — the client failed to carry it, or the item is still sitting in the domain and there was nothing to carry — and a test which only watches the server cannot tell them apart. The local side is checked first so that a failure says which half broke.
            #expect(try LocalNode.at(url) == nil, """
            Removing the item in the client left it in place: it is still at \(url.path(percentEncoded: false)) after `removeItem` returned without error. Nothing about what the server does or does not do follows from this.
            """)

            var reachedServer = true

            do {
                try await Waiter.poll("the server lets go of \"\(name)\"", timeout: LiveEnvironment.scaled(.seconds(180))) {
                    try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == name }
                }
            } catch is WaitTimeoutError {
                reachedServer = false
            }

            // Read again, now that time has passed. The check immediately after `removeItem` says the unlink happened; this says whether it lasted — and the difference matters more than it looks. An item which is gone and stays gone while the server keeps it is a permanent divergence and silent data retention. An item which comes back is a deletion the provider reverted, which is a different defect, less alarming, and lives in different code. Asserting the first while only having measured the second would send a maintainer to the wrong place.
            let survivor = try LocalNode.at(url)

            #expect(reachedServer, """
            Deleting the item in the client never reached the server. The item is \(survivor == nil ? "gone from the client, so the two sides now disagree permanently and the user has lost a deletion they watched happen" : "back in the client, so the deletion was reverted rather than lost"), and the File Provider extension's own log for this room says whether it was ever asked to perform the deletion at all.
            """)

            guard reachedServer else {
                return
            }

            MetricsRecorder.record("client to server deletion", duration: ContinuousClock.now - started, in: room, test: cell.description)

            // With the trash disabled the API gives no contract for where a deleted item goes — the system decides, and the destination is explicitly not guaranteed. So where it went is recorded rather than asserted; what must hold either way is that it is gone from the domain, which is checked above.
            guard cell.trash == .with else {
                let remains = (try? await room.server.trash()) ?? []

                UnderdeterminedOutcome.observed(remains.contains { $0.name == name } ? "providerDefinedDestination" : "removedPermanently", for: .trashPlacement, in: cell)

                ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
                ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
                ScenarioOracle.decline("realizationState", because: ScenarioOracle.deletedItemReason)
                ScenarioOracle.decline("contentMatch", because: ScenarioOracle.trashContentReason)

                return
            }

            let trashed = try await room.server.trash()

            guard let entry = trashed.first(where: { $0.name == name }) else {
                Issue.record("""
                The item was deleted in the client and never reached the server's trash, so a user who deletes a file in the Finder cannot get it back. The trash holds: \(trashed.map(\.name).sorted().joined(separator: ", ")).
                """)

                return
            }

            #expect(entry.isDirectory == (cell.item.kind != .file), "The trashed item changed from a file to a directory or the reverse on its way into the trash.")

            if cell.item.kind == .file, let size = entry.size, let expected = ScenarioWorld.bytes(for: cell.item.size) {
                #expect(size == UInt64(expected), "The trashed copy is \(size) bytes where the file was \(expected).")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.deletedItemReason)
            ScenarioOracle.decline("contentMatch", because: ScenarioOracle.trashContentReason)
        }
    }
}
