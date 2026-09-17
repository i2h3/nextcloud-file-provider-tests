// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// The same item renamed on both sides at once, to two different names.
///
/// The quadrant where ``ScenarioMatrix/Oracle/conflictResolution`` can finally be judged rather than declined. Its permitted results — a conflict copy, the server's version winning, the local one winning — are indistinguishable when both sides delete an item and invisible when only one side acts. Two different names make all three visible at once: the item ends up under the name the client chose, the name the server chose, or both.
///
/// Which of them happens is **not** asserted. The specification permits every one, and this project has already reported a correct client as defective by picking a favourite — the first version of ``ConflictTests`` did exactly that. ``UnderdeterminedOutcome`` is the only way this suite is allowed to speak about the clause, and it offers membership and nothing else.
///
/// What *is* asserted is the invariant common to all three: the item survives. A rename on both sides may be resolved in favour of either name, and may keep both, but an item which ends up under neither name has been lost by a system that was asked twice to keep it under a name.
///
@Suite("Concurrent metadata update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct ConcurrentMetadataUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .concurrent, operation: .metadataUpdate), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item renamed on both sides at once survives under one of the permitted names.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item renamed on both sides at once survives under one of the permitted names.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "ConcurrentMetadataUpdate.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let isFile = cell.item.kind == .file
            let before = isFile ? "before.bin" : "before"
            let byClient = isFile ? "by-client.bin" : "by-client"
            let byServer = isFile ? "by-server.bin" : "by-server"

            let subject = try await ScenarioWorld.build(cell, in: room, named: before)
            let oldURL = room.localURL(of: subject.localPath(of: before))
            let newURL = room.localURL(of: subject.localPath(of: byClient))

            let started = ContinuousClock.now

            // Issued together, and without pausing the item: the contract the model assigns a concurrent cell is the unpaused one, so arranging a cleaner divergence by pausing would establish a different cell than the one being claimed.
            async let serverRename: Void = room.server.move(subject.remotePath, to: subject.remotePath(of: byServer), overwrite: false)

            try FileManager.default.moveItem(at: oldURL, to: newURL)

            // A refusal is an outcome rather than an error: if the client's rename arrived first, the server no longer has the item under its old name.
            let serverAcceptedRename: Bool

            do {
                try await serverRename
                serverAcceptedRename = true
            } catch {
                serverAcceptedRename = false
            }

            try await Waiter.poll("the server settles on a name", timeout: LiveEnvironment.scaled(.seconds(240))) {
                try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == before }
            }

            MetricsRecorder.record("concurrent rename", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let names = Set(try await room.remoteChildren(of: subject.parentRemotePath).map(\.name))
            let member: String?

            switch (names.contains(byClient), names.contains(byServer)) {
                case (true, true): member = "conflictCopy"
                case (true, false): member = "localWon"
                case (false, true): member = "serverWon"
                case (false, false): member = nil
            }

            // The invariant every permitted result shares, and the only thing this suite is entitled to demand. An item under neither name was renamed out of existence by a system asked twice to keep it under a name.
            guard let member else {
                Issue.record("""
                The item was renamed to "\(byClient)" in the client and to "\(byServer)" on the server, and afterwards the server holds neither. The server \(serverAcceptedRename ? "accepted its own rename" : "refused its own rename, so the client's had already arrived"), and the item is gone. It holds: \(names.sorted().joined(separator: ", ")).
                """)

                return
            }

            UnderdeterminedOutcome.observed(member, for: .conflictResolution, in: cell)

            // Common to every permitted result: whatever name it settled under, the item is the same item and its content did not change. A rename resolved by replacing the item is a legal-looking outcome which has thrown away the shares, comments and history the server kept.
            if member != "conflictCopy", let survivor = try await room.remoteChildren(of: subject.parentRemotePath).first(where: { $0.name == byClient || $0.name == byServer }) {
                #expect(survivor.fileIdentifier == subject.before.fileIdentifier, """
                The item which survived the rename has a different identity from the one which went into it: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(survivor.fileIdentifier ?? "unknown"). Its shares, comments and version history belong to an item which no longer exists.
                """)
            }

            if let fingerprint = subject.fingerprint, member != "conflictCopy" {
                let surviving = names.contains(byClient) ? byClient : byServer

                #expect(try await room.remoteFingerprint(of: subject.remotePath(of: surviving)) == fingerprint, """
                The content of the item changed while both sides were renaming it, and neither side asked for its content to change.
                """)
            }

            // Whichever way it resolved, the two sides have to end up agreeing about it.
            try await Waiter.waitUntilBlocking("the client agrees with the server about the name", timeout: LiveEnvironment.scaled(.seconds(240))) {
                let local = Set(try room.localChildren(of: subject.parentLocalPath).map(\.name))

                return local.intersection([byClient, byServer]) == names.intersection([byClient, byServer])
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)

        }
    }
}
