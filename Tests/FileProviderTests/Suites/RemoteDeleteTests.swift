// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item deleted on the server, and whether the client lets go of it.
///
/// The second generated quadrant, and chosen because deletion is where the two sides disagree most expensively: an item the client keeps after the server has dropped it is a file a user believes is backed up and is not, and an item the client drops without the server agreeing is data loss with no trace.
///
/// It also exercises something no other suite here reaches. Deletion on a Nextcloud server is not removal — it is a move into the trash bin, and the item is expected to be recoverable from it with its original location intact. That path has never been tested from the server side in this project, and ``ScenarioMatrix/Oracle/trashPlacement`` is the clause that judges it.
///
/// ## The trash bin is a setting, not a fact
///
/// Keeping deleted items is an application on a Nextcloud server and an administrator can turn it off. The model knows this — ``ScenarioMatrix/TrashSupport`` is an axis, and its `without` value carries an **underdetermined** contract, because with trash syncing unsupported the system decides what to do with a trashing operation and the destination is explicitly not guaranteed by the API contract.
///
/// The cells here are all `trash:with`, and that assumption is **read back from the server** before any of them runs rather than trusted. Against a server with the trash disabled these twelve would otherwise produce twelve failures reading *the item was deleted and never reached the trash* — a complete and entirely wrong bug report about a client behaving correctly. Confirming it instead makes such a run report that the cells were not measured, which is what actually happened.
///
/// The `trash:without` cells are sixty rows this harness does not yet run. They need a second server profile with `files_trashbin` disabled, and they must never assert a single destination when the specification permits a set.
///
/// ## What these cells do not assert
///
/// Every cell of this quadrant carries five clauses. Three are evaluated — the two sides agreeing, the item reaching the trash, and the trashed copy still being the item that was deleted. Two are declined by name, for the same reasons as in ``RemoteMetadataUpdateTests``, with one addition of its own: after a deletion there is no item left, so asserting anything about its realization is asserting that it is gone, which is the consistency check under another name.
///
@Suite("Remote delete", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct RemoteDeleteTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    /// Twelve of the quadrant's fifty-two. The largest single exclusion is `trash:without`, which needs the server's trash application disabled and read back through its capabilities — a server profile rather than a test, and the one primitive that would most enlarge this suite.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .remote, operation: .delete), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item deleted on the server disappears from the client and is recoverable from the trash.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item deleted on the server disappears from the client and lands in the trash.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "RemoteDelete.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let name = cell.item.kind == .file ? "doomed.bin" : "doomed"
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)

            let started = ContinuousClock.now
            try await room.server.delete(subject.remotePath)

            // `lstat` on the one path, never a listing of the parent. A cell whose precondition is that the item was never enumerated cannot be judged by enumerating it, and half of these cells are exactly that.
            let url = room.localURL(of: subject.localPath(of: name))

            try await Waiter.waitUntilBlocking("\"\(name)\" disappears from the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try LocalNode.at(url) == nil
            }

            MetricsRecorder.record("server to client deletion", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let remaining = try await room.remoteChildren(of: subject.parentRemotePath).map(\.name).sorted()

            #expect(!remaining.contains(name), """
            The server still holds the item after deleting it. It holds: \(remaining.joined(separator: ", ")).
            """)

            // The clause this quadrant exists for. A deletion on Nextcloud is a move into the trash, and an item which vanishes instead of arriving there is data a user cannot get back.
            let trashed = try await room.server.trash()

            guard let entry = trashed.first(where: { $0.name == name }) else {
                Issue.record("""
                The item was deleted from the server and never reached the trash, so nothing about it is recoverable. The trash holds: \(trashed.map(\.name).sorted().joined(separator: ", ")).
                """)

                return
            }

            #expect(entry.originalLocation.hasSuffix(subject.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), """
            The trashed item does not remember where it came from: it records "\(entry.originalLocation)" where the item was deleted from "\(subject.remotePath)". A restore then puts it somewhere other than where the user lost it.
            """)

            #expect(entry.isDirectory == (cell.item.kind != .file), "The trashed item changed from a file to a directory or the reverse on its way into the trash.")

            // The byte-level comparison is declined rather than attempted: reading content back out of the trash needs a download against the trash endpoint, which the WebDAV client here does not expose. The size is what it will give, and it is worth having.
            if cell.item.kind == .file, let size = entry.size {
                #expect(size == UInt64(ScenarioWorld.smallFileSize), "The trashed copy of the file is \(size) bytes where the file was \(ScenarioWorld.smallFileSize).")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)

            ScenarioOracle.decline("realizationState", because: """
            After a deletion there is no item left to be a placeholder or to be materialized, so any assertion about its realization reduces to asserting that it is gone — which is the consistency clause under another name, and is checked there.
            """)

            ScenarioOracle.decline("contentMatch", because: """
            Comparing the bytes of the trashed copy needs a download against the server's trash endpoint, which the WebDAV client used here does not expose. Its recorded size is asserted instead, which catches a truncated or empty copy but not a corrupted one.
            """)
        }
    }
}
