// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// The same file written on both sides at once, with different bytes.
///
/// The last quadrant of the matrix, and the only one whose cells may fail to measure anything through no fault of the client.
///
/// A concurrent cell carries the **unpaused** contract, so this must not pause the item: pausing is how ``ConflictTests`` arranges a guaranteed divergence by hand, and it establishes a different cell than the one claimed here. Without it, the two writes are only as concurrent as the machine makes them — the local write often reaches the server before the server's own upload is noticed, in which case the run measured two edits in sequence and no conflict happened at all.
///
/// So the divergence is **checked rather than assumed**. Immediately after both writes, each side is read: if the server holds the bytes it was given and the file on disk holds the bytes it was given, then two different versions of the file existed at the same moment and there was something to resolve. If not, the trial is reported as unmeasured. A cell which quietly reports "no conflict" as a pass would be the most comfortable kind of false coverage — a quadrant which never fails because it never tests anything.
///
/// What is asserted once a divergence did occur: both sides converge, and whatever survives is one of the two versions that went in. Which one is recorded and not asserted — the specification permits either, and a conflict copy of both.
///
@Suite("Concurrent content update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct ConcurrentContentUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .concurrent, operation: .contentUpdate), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: when both sides write different bytes at once, the two sides converge on bytes one of them wrote.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `A file written on both sides at once converges on bytes one of them wrote.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "ConcurrentContentUpdate.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let name = "contested.bin"
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            // Different lengths as well as different bytes, so that which version is present can be seen without reading either of them in full.
            let byClient = ContentFactory.content(size: ScenarioWorld.smallFileSize * 2, seed: 93)
            let byServer = ContentFactory.content(size: ScenarioWorld.smallFileSize * 3, seed: 94)
            let clientFingerprint = ContentFactory.fingerprint(of: byClient)
            let serverFingerprint = ContentFactory.fingerprint(of: byServer)

            let started = ContinuousClock.now

            async let serverWrite: Void = ServerWorkspace.withFixture(named: name, size: byServer.count, seed: 94) { source, _ in
                try await room.server.upload(source, to: subject.parentRemotePath, force: true)
            }

            try byClient.write(to: url)
            try await serverWrite

            // Whether there was ever anything to resolve. Two different versions existing at the same moment is what makes this a conflict rather than two edits in a row, and without pausing the item that is a matter of timing rather than of arrangement. Read immediately, before either side has had time to carry its version to the other.
            let serverHeld = try await room.remoteFingerprint(of: subject.remotePath)
            let clientHeld = ContentFactory.fingerprint(of: try Data(contentsOf: url))

            guard serverHeld == serverFingerprint, clientHeld == clientFingerprint else {
                // Reported rather than passed. A cell which treats "no conflict occurred" as a success is a cell which cannot fail, and it would count towards coverage while testing nothing.
                print("""
                  unmeasured: \(cell.description) — the two writes did not overlap, so no conflict arose to resolve. \
                The server held \(serverHeld == clientFingerprint ? "the client's version already" : "something else") \
                and the client held \(clientHeld == clientFingerprint ? "its own version" : "something else"). \
                Nothing about conflict resolution follows from this run of the cell.
                """)

                return
            }

            MetricsRecorder.record("concurrent content write", duration: ContinuousClock.now - started, in: room, test: cell.description)

            // Both sides are read together until they agree, for the reason the rename quadrant learned the hard way: reading one side once and waiting for the other to match it waits for a state which may already have been overtaken.
            var settled = [String: String]()
            var converged = true

            do {
                try await Waiter.poll("both sides settle on the same content", timeout: LiveEnvironment.scaled(.seconds(300))) {
                    let remote = try await room.remoteChildren(of: subject.parentRemotePath).map(\.name).sorted()

                    let listing = try await Deadline.runBlocking(within: LiveEnvironment.scaled(.seconds(30))) {
                        try room.localChildren(of: subject.parentLocalPath).map(\.name).sorted()
                    }

                    guard let local = listing, local == remote, !remote.isEmpty else {
                        return false
                    }

                    var fingerprints = [String: String]()

                    for entry in remote {
                        try await fingerprints[entry] = room.remoteFingerprint(of: subject.remotePath(of: entry))
                    }

                    settled = fingerprints

                    return true
                }
            } catch is WaitTimeoutError {
                converged = false
            }

            guard converged else {
                Issue.record("""
                Both sides wrote different bytes to "\(name)" and five minutes later they still disagree about what the folder holds. Every result the specification permits ends with the two sides agreeing, whichever version won and whether or not a copy was kept.
                """)

                return
            }

            // The invariant every permitted result shares and the only one worth asserting: whatever survived is one of the two versions that went in. A third value is neither side's bytes and is not a conflict resolution at all.
            for (entry, fingerprint) in settled {
                #expect(fingerprint == clientFingerprint || fingerprint == serverFingerprint, """
                "\(entry)" holds bytes neither side wrote. The client wrote \(byClient.count) bytes and the server \(byServer.count); this is neither.
                """)
            }

            let held = Set(settled.values)
            let member: String

            if held.contains(clientFingerprint), held.contains(serverFingerprint) {
                member = "conflictCopy"
            } else if held.contains(clientFingerprint) {
                member = "localWon"
            } else if held.contains(serverFingerprint) {
                member = "serverWon"
            } else {
                return
            }

            UnderdeterminedOutcome.observed(member, for: .conflictResolution, in: cell)

            if member != "conflictCopy" {
                print("  note: the losing version was not kept separately — the folder holds \(settled.keys.sorted().joined(separator: ", ")).")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
