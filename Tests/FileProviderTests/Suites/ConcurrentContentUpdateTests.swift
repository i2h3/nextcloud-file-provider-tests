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
    static let cells: [Scenario] = ScenarioSelection.cells(of: Quadrant(origin: .concurrent, operation: .contentUpdate))

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

        try await CleanRoom.with(underTest, testName: "ConcurrentContentUpdate.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let name = "contested.bin"
            let subject = try await ScenarioWorld.build(cell, in: room, named: name)
            let url = room.localURL(of: subject.localPath(of: name))

            // Different lengths as well as different bytes, so that which version is present can be seen without reading either of them in full.
            let byClient = ContentFactory.content(size: ScenarioWorld.smallFileSize * 2, seed: 93)
            let byServer = ContentFactory.content(size: ScenarioWorld.smallFileSize * 3, seed: 94)
            let clientFingerprint = ContentFactory.fingerprint(of: byClient)
            let serverFingerprint = ContentFactory.fingerprint(of: byServer)

            // A package's bytes live in a file inside it. The model puts files and bundles in the same class — a content update is legal on both — and this is where that costs a line.
            let inside = ScenarioWorld.contentComponent(of: cell.item.kind)
            let contentURL = inside.map { url.appending(path: $0, directoryHint: .notDirectory) } ?? url
            let contentRemotePath = inside.map { "\(subject.remotePath)/\($0)" } ?? subject.remotePath

            let started = ContinuousClock.now

            async let serverWrite: Void = ServerWorkspace.withFixture(named: inside ?? name, size: byServer.count, seed: 94) { source, _ in
                try await room.server.upload(source, to: inside == nil ? subject.parentRemotePath : subject.remotePath, force: true)
            }

            try byClient.write(to: contentURL)
            try await serverWrite

            // Whether there was ever anything to resolve. Two different versions existing at the same moment is what makes this a conflict rather than two edits in a row, and without pausing the item that is a matter of timing rather than of arrangement. Read immediately, before either side has had time to carry its version to the other.
            let serverHeld = try await room.remoteFingerprint(of: contentRemotePath)
            let clientHeld = try ContentFactory.fingerprint(of: Data(contentsOf: contentURL))

            guard serverHeld == serverFingerprint, clientHeld == clientFingerprint else {
                // Reported rather than passed. A cell which treats "no conflict occurred" as a success is a cell which cannot fail, and it would count towards coverage while testing nothing.
                //
                // Recorded as well as printed, because a printed one is a cell which counts towards coverage while testing nothing *and leaves no trace of having done so*. The run's page shows this row as a cell that ran; the note underneath it is the only thing that says it measured nothing.
                ScenarioOracle.observe("""
                the two writes did not overlap, so no conflict arose to resolve. \
                The server held \(serverHeld == clientFingerprint ? "the client's version already" : "something else") \
                and the client held \(clientHeld == clientFingerprint ? "its own version" : "something else"). \
                Nothing about conflict resolution follows from this run of the cell
                """, in: room)

                return
            }

            MetricsRecorder.record("concurrent content write", duration: ContinuousClock.now - started, in: room, test: cell.description)

            /// Where an entry's bytes live, which is the entry itself for a file and a file inside it for a package.
            func contentPaths(of entry: String) -> (local: URL, remote: String) {
                let base = room.localURL(of: subject.localPath(of: entry))

                return (
                    inside.map { base.appending(path: $0, directoryHint: .notDirectory) } ?? base,
                    inside.map { "\(subject.remotePath(of: entry))/\($0)" } ?? subject.remotePath(of: entry)
                )
            }

            /// How long each side's copy of an entry is, read without materializing either.
            ///
            /// By length rather than by bytes, which is what the two versions were given different lengths for. Reading a placeholder to compare its content is how a test materializes the thing it is measuring, and a conflict copy the client has not fetched is a placeholder — one which still reports the size of the file it stands for.
            func lengths(of entry: String) async throws -> (local: Int64, remote: Int64)? {
                let paths = contentPaths(of: entry)

                guard let node = try LocalNode.at(paths.local) else {
                    return nil
                }

                let container = inside == nil ? subject.parentRemotePath : subject.remotePath(of: entry)
                let name = inside ?? entry

                guard let size = try await room.remoteChildren(of: container).first(where: { $0.name == name })?.size else {
                    return nil
                }

                return (node.size, size)
            }

            // Both sides are read together until they agree, for the reason the rename quadrant learned the hard way: reading one side once and waiting for the other to match it waits for a state which may already have been overtaken.
            //
            // And read for their *content*, which this said it did and did not do. The condition compared two lists of names — and no name changes in this quadrant, so for a cell in a subdirectory both lists read `["contested.bin"]` on the very first evaluation, before the client had uploaded anything. The wait returned instantly, `settled` captured the server's own upload, and which version won a content conflict — the entire output of this quadrant — was decided by a read taken before resolution began. The timeout branch below was unreachable.
            //
            // The rename quadrant escapes this because its two candidate names exist on neither side until the rename resolves. Content has no such marker, so lengths are the marker, and they are compared per entry across the two sides.
            //
            // The local listing also drops what the domain root carries and the server does not. A cell at the root compared `[".Trash", "contested.bin"]` against `["contested.bin"]`, which never agree — so that half of the quadrant would have spent five minutes and then recorded a finished bug report about the client for an entry the system had put there.
            var settled = [String: String]()
            var converged = true

            do {
                try await Waiter.poll("both sides settle on the same content", timeout: LiveEnvironment.scaled(.seconds(300))) {
                    let remote = try await room.remoteChildren(of: subject.parentRemotePath).map(\.name).sorted()

                    let listing = try await Deadline.runBlocking(within: LiveEnvironment.scaled(.seconds(30))) {
                        try room.localChildren(of: subject.parentLocalPath)
                            .map(\.name)
                            .filter { !LocalDirectory.systemEntryNames.contains($0) }
                            .sorted()
                    }

                    guard let local = listing, local == remote, !remote.isEmpty else {
                        return false
                    }

                    for entry in remote {
                        guard let measured = try await lengths(of: entry), measured.local == measured.remote else {
                            return false
                        }
                    }

                    var fingerprints = [String: String]()

                    for entry in remote {
                        try await fingerprints[entry] = room.remoteFingerprint(of: contentPaths(of: entry).remote)
                    }

                    settled = fingerprints

                    return true
                }
            } catch is WaitTimeoutError {
                converged = false
            }

            guard converged else {
                Issue.record("""
                Both sides wrote different bytes to "\(name)" and five minutes later they still hold different bytes for it. The client wrote \(byClient.count) bytes and the server \(byServer.count). Every result the specification permits ends with the two sides agreeing, whichever version won and whether or not a copy was kept.
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

            UnderdeterminedOutcome.observed(member, for: .conflictResolution, in: cell, room: room)

            if member != "conflictCopy" {
                print("  note: the losing version was not kept separately — the folder holds \(settled.keys.sorted().joined(separator: ", ")).")
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
