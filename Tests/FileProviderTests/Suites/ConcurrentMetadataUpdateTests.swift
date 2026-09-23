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
    static let cells: [Scenario] = ScenarioSelection.cells(of: Quadrant(origin: .concurrent, operation: .metadataUpdate))

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

        try await CleanRoom.with(underTest, testName: "ConcurrentMetadataUpdate.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
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

            // Both sides are read together, on every attempt, until they agree — and the winner is named from what they agreed on rather than from a snapshot.
            //
            // The first version of this read the server once, called that the result, and then waited for the client to match it. It could not work. The only thing that first read proved had happened was this test's own server-side rename, which lands instantly; the client's rename was still in flight and could overtake it afterwards, leaving the test comparing both settled sides against a state neither of them held any more. Ten of twelve cells failed that way, and the two which passed were the two where the snapshot happened to be right.
            var settled = Set<String>()
            var converged = true

            do {
                try await Waiter.poll("both sides settle on the same name", timeout: LiveEnvironment.scaled(.seconds(240))) {
                    let remote = try await Set(room.remoteChildren(of: subject.parentRemotePath).map(\.name)).intersection([byClient, byServer])

                    // Listing the domain blocks in the kernel, so it is read on a thread of its own rather than on the cooperative pool.
                    let listing = try await Deadline.runBlocking(within: LiveEnvironment.scaled(.seconds(30))) {
                        try Set(room.localChildren(of: subject.parentLocalPath).map(\.name))
                    }

                    guard let local = listing?.intersection([byClient, byServer]), !remote.isEmpty, remote == local else {
                        return false
                    }

                    settled = remote

                    return true
                }
            } catch is WaitTimeoutError {
                converged = false
            }

            guard converged else {
                let remote = try await Set(room.remoteChildren(of: subject.parentRemotePath).map(\.name)).intersection([byClient, byServer])
                let local = try Set(room.localChildren(of: subject.parentLocalPath).map(\.name)).intersection([byClient, byServer])

                Issue.record("""
                The item was renamed to "\(byClient)" in the client and to "\(byServer)" on the server, and four minutes later the two sides still disagree about what it is called. The server holds \(remote.isEmpty ? "neither name" : remote.sorted().joined(separator: ", ")) and the client holds \(local.isEmpty ? "neither name" : local.sorted().joined(separator: ", ")). The server \(serverAcceptedRename ? "accepted its own rename" : "refused its own rename, so the client's had already arrived").

                Every result the specification permits has both sides ending up with the same name or names. A file which is called one thing on the server and another on the Mac is none of them.
                """)

                return
            }

            // The invariant every permitted result shares, and the only thing this suite is entitled to demand beyond convergence.
            let member: String

            switch (settled.contains(byClient), settled.contains(byServer)) {
                case (true, true): member = "conflictCopy"
                case (true, false): member = "localWon"
                case (false, true): member = "serverWon"
                case (false, false): return
            }

            UnderdeterminedOutcome.observed(member, for: .conflictResolution, in: cell, room: room)

            // Common to every permitted result: whatever name it settled under, the item is the same item and its content did not change. A rename resolved by replacing the item is a legal-looking outcome which has thrown away the shares, comments and history the server kept.
            if member != "conflictCopy", let survivor = try await room.remoteChildren(of: subject.parentRemotePath).first(where: { settled.contains($0.name) }) {
                #expect(survivor.fileIdentifier == subject.before.fileIdentifier, """
                The item which survived the rename has a different identity from the one which went into it: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(survivor.fileIdentifier ?? "unknown"). Its shares, comments and version history belong to an item which no longer exists.
                """)
            }

            if let fingerprint = subject.fingerprint, member != "conflictCopy", let surviving = settled.first {
                #expect(try await room.remoteFingerprint(of: subject.remotePath(of: surviving)) == fingerprint, """
                The content of the item changed while both sides were renaming it, and neither side asked for its content to change.
                """)
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
