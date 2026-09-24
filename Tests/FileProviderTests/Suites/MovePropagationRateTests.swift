// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// How often a move made on the server reaches the client, and whether the destination having been opened decides it.
///
/// Not a contract test. ``RemoteMoveTests`` already asserts that an item moved on the server moves in the client, and it fails when that does not happen — but it runs each cell once, and what it found does not happen every time. Two runs of sixty cells produced eight failures. Every one of them moved an item into a container the client had never enumerated; none of the eighty cell-runs whose destination had been listed failed at all; and the failing cells were not the same on both days — two which failed on the twenty-third passed on the twenty-fourth, in eighteen and twenty-five seconds.
///
/// That is enough to know something is there and confined to one shape, and not enough for a bug report. This measures.
///
/// ## The comparison is inside the run
///
/// Each kind of item is moved into a container the client has opened and into one it has not, and nothing else differs between the two. A rate on its own would be a number anybody could attribute to a slow machine or a busy Docker; a rate beside its control, taken minutes apart on the same client against the same server, is a difference.
///
/// The source container is held materialized throughout for the same reason. The model also emits moves *out of* an unopened container, and those have never failed — including them would vary two things at once and leave the result unable to say which mattered.
///
/// ## What it is careful about
///
/// **It asserts almost nothing.** A characterisation suite which fails is one nobody runs twice, and the failure is already asserted in ``RemoteMoveTests``. The only expectation here is that the server performed the move, because a trial where the item never moved is not a sample of anything.
///
/// **Arrived and departed are counted separately.** The contract suite waits for a conjunction — the item is at its destination *and* gone from its source — and a trial can miss it two ways. A client which never heard about the move leaves the item where it was; one which copied rather than moved leaves it in both places. Those are different defects in different code, so they are counted apart rather than summed into one rate.
///
/// **Trials share a room, and that is the limitation to read every number here through.** Building a clean room takes about eighty seconds against a trial's thirty, so a room per trial puts a hundred samples out of reach. The trials therefore run against one account, one domain and one client which has been running for a while, and these are rates *within one session* — the same caveat ``DeletionPropagationRateTests`` carries, learned there the hard way.
///
/// **A trial which cannot be set up is dropped rather than counted.** Building the world can fail on its own, and such a trial says nothing about moving either way.
///
@Suite("Move propagation rate", .requiresLiveEnvironment, .requiresRepetitions, .serialized, .timeLimit(.minutes(120)))
struct MovePropagationRateTests {
    ///
    /// How long a single trial waits for the client before calling the move not propagated.
    ///
    /// Longer than the deletion suite's ten seconds, and it has to be. Every successful server-to-client move measured so far — a hundred and twelve of them across two runs — took between 28.8 and 30.9 seconds, with one exception at 0.3. That is not a distribution around a mean; it is a poll interval, and a timeout inside it would measure the polling rather than the client.
    ///
    /// Sixty seconds is twice the observed interval, so a move which merely missed one poll is still counted as having arrived.
    ///
    static let trialTimeout = Duration.seconds(60)

    ///
    /// How long a trial keeps watching after it has already been counted as not propagating.
    ///
    /// The distinction the whole suite exists to make. A move which never reaches the client is a divergence the user cannot see — the file is somewhere they did not put it, and the place they did is empty; a move which arrives at three minutes is a delay. They are different defects, they live in different code, and a report which confuses them sends a maintainer to the wrong half of the client.
    ///
    /// Three further poll intervals, because a client which missed one poll and recovered on the next is exactly what "late" would look like here.
    ///
    static let graceTimeout = Duration.seconds(120)

    ///
    /// Which way a trial ended.
    ///
    /// Four outcomes rather than two, because the contract suite's condition is a conjunction and a bare "did not propagate" cannot say which half of it failed.
    ///
    enum Outcome: String, Sendable {
        ///
        /// The item is at its destination and gone from its source, inside ``trialTimeout``.
        ///
        case moved

        ///
        /// The same, but only after ``trialTimeout`` and within ``graceTimeout``.
        ///
        case late

        ///
        /// The item reached its destination and was left at its source as well, so what arrived was a copy.
        ///
        case copied

        ///
        /// The item never reached its destination.
        ///
        case lost
    }

    ///
    /// One cell run many times, which is what a case of this suite is.
    ///
    /// A pair rather than two argument lists, because the testing library takes at most two collections and the server is one of them.
    ///
    struct Trial: Sendable, CustomStringConvertible, CustomTestArgumentEncodable {
        ///
        /// The state to establish and move.
        ///
        let cell: Scenario

        ///
        /// How the cell names itself in a run.
        ///
        var description: String {
            cell.description
        }

        ///
        /// Implementation for `CustomTestArgumentEncodable` conformance.
        ///
        /// - Parameters:
        ///     - encoder: The encoder to write to.
        ///
        /// - Throws: Whatever encoding raises.
        ///
        func encodeTestArgument(to encoder: some Encoder) throws {
            var container = encoder.singleValueContainer()

            try container.encode(description)
        }
    }

    ///
    /// The cells whose behaviour is being measured, and their controls.
    ///
    /// Drawn from what ``RemoteMoveTests`` runs rather than assembled here, so that a cell this harness stops being able to build disappears from the measurement instead of failing inside it.
    ///
    /// Narrowed to one axis. The source is materialized, the direction is always from the root into a subdirectory, and the only thing which differs between a subject and its control is whether the client has ever opened the folder the item arrives in. The encodings are left out — the failures spanned a collision, a decomposed name and no encoding at all, so the encoding is not what these are about, and carrying four of them would quadruple a suite whose trials cost half a minute each.
    ///
    /// Eight cells: four kinds of item, each moved into an opened folder and into an unopened one.
    ///
    static let trials: [Trial] = RemoteMoveTests.cells
        .filter { cell in
            guard cell.encoding == nil else {
                return false
            }

            guard case let .parents(source, destination) = cell.realization else {
                return false
            }

            guard case let .transfer(_, arrival) = cell.site else {
                return false
            }

            // The direction is held fixed as well as the source. A dataless destination can only be a subdirectory — the model rules a dataless root out, because the root is enumerated as the domain mounts — so a control which also moved the other way would differ from its subject in two things and settle neither.
            guard arrival.location == .subdirectory else {
                return false
            }

            return source == .materialized && (destination == .dataless || destination == .materialized)
        }
        .map(Trial.init)

    ///
    /// Move the same kind of item many times and report how often the client followed it.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - trialCase: The cell to establish and move, repeatedly.
    ///
    @Test(arguments: LiveEnvironment.servers, trials)
    func `Moving the same item repeatedly shows how often the move reaches the client.`(_ underTest: ServerUnderTest, _ trialCase: Trial) async throws {
        let cell = trialCase.cell

        guard case let .parents(source, destination) = cell.realization else {
            throw ScenarioWorldError.unsupported("a move whose realization does not describe its two containers")
        }

        guard let trials = RunEnvironment.repetitions() else {
            throw ScenarioWorldError.unsupported("a characterisation run, which needs \(RunEnvironment.repetitionsVariableName) set")
        }

        try await CleanRoom.with(underTest, testName: "MovePropagationRate.\(cell.item.kind.rawValue).\(source.rawValue)-\(destination.rawValue)", cell: cell.description) { room in
            // Reported while the trials run rather than only after them. A cell is many repetitions of something which takes half a minute each, and a suite which prints nothing for an hour is indistinguishable from one which has stopped.
            print("  cell: \(cell.description), \(trials) repetitions")

            func note(_ trial: Int, _ outcome: String) {
                print("        trial \(trial) of \(trials): \(outcome)")
            }

            // Taken from the world rather than named here, so that the container this suite looks in cannot drift from the one ``ScenarioWorld`` builds.
            var destinationContainer: String?

            var counts = [Outcome: Int]()
            var dropped = 0
            var latencies = [Duration]()
            var lateLatencies = [Duration]()

            for trial in 1 ... trials {
                let name = ScenarioWorld.name("trial-\(trial)", for: cell.item.kind, encoding: cell.encoding)
                let subject: ScenarioSubject

                do {
                    subject = try await ScenarioWorld.build(cell, in: room, named: name)
                } catch {
                    // The world would not build, so this trial is a sample of nothing. Counting it either way would put a fault in the setting up into a number about the client.
                    dropped += 1
                    note(trial, "dropped, because its world would not build: \(error)")

                    continue
                }

                guard let destinationLocal = subject.destinationLocal, let destinationRemote = subject.destinationPath else {
                    dropped += 1
                    note(trial, "dropped, because the world built without a destination")

                    continue
                }

                // `destinationLocal` is already the item's whole path after the move, name included, which is how ``RemoteMoveTests`` uses it. Joining the name onto it again produced a path one level below where the item lands — `box/trial-1.bin/trial-1.bin` — which cannot exist, so every trial of every cell was counted as lost. Eighty of them, in four and three quarter hours, including the control arm which had moved fifty-six items out of sixty the day before.
                destinationContainer = subject.destinationLocalPath

                let from = room.localURL(of: subject.localPath(of: name))
                let to = room.localURL(of: destinationLocal)
                let started = ContinuousClock.now

                try await room.server.move(subject.remotePath, to: destinationRemote, overwrite: false)

                // The server's own work is asserted rather than measured. A trial where the move did not happen on the server is not a sample of what the client does with one.
                #expect(try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == name }, """
                Trial \(trial): the server still holds the item at its old path, so this trial measures nothing about propagation.
                """)

                let outcome = try await observe(trial: trial, from: from, to: to, started: started, note: note, into: &latencies, and: &lateLatencies)

                counts[outcome, default: 0] += 1

                // Put the server back, or the next trial is not a fresh sample. The item is deleted rather than moved home, because a move back is another move and would be measured by the client as one.
                try? await room.server.delete(destinationRemote)
            }

            let counted = counts.values.reduce(0, +)

            guard counted > 0 else {
                Issue.record("Every trial of \(cell.description) failed to build, so nothing was measured.")

                return
            }

            // A cell where not one trial arrived is more likely a broken instrument than a client which lost every single move, and this suite asserts so little that a broken instrument otherwise reports itself as a pass. It did: a path built one level too deep scored nought out of eighty, control arm included, and the run ended green.
            //
            // Said as an issue rather than swallowed, and said as a doubt about the measurement rather than as a finding about the client — because a genuine total loss is possible and must not be suppressed by the guard against a mistake.
            if (counts[.moved] ?? 0) == 0, (counts[.late] ?? 0) == 0, (counts[.copied] ?? 0) == 0 {
                Issue.record("""
                Not one of \(counted) moves arrived, so this cell measured either a client which loses every move of this shape or a harness which was watching the wrong place. \
                The destination held \(destinationContainer.map { ScenarioWorld.describe($0, in: room) } ?? "nothing this could look at") when the trials were over. \
                Read once, here, and never during the trials: listing a container is how it stops being unentered, and half of these cells are about a destination the client has never opened. \
                Establish which of the two it was before treating the rate below as a finding.
                """)
            }

            report(counts, counted: counted, dropped: dropped, latencies: latencies, lateLatencies: lateLatencies, for: cell, in: room, against: underTest)
        }
    }

    ///
    /// Watch both paths until the move has plainly arrived, plainly not, or arrived as a copy.
    ///
    /// Both ends, because watching only the destination cannot tell a move from a copy, and this suite exists to tell them apart.
    ///
    /// - Parameters:
    ///     - trial: Which repetition this is, for the running commentary.
    ///     - from: Where the item was.
    ///     - to: Where it should be.
    ///     - started: When the server was asked.
    ///     - note: How to say what happened.
    ///     - latencies: Where to put the duration of an on-time arrival.
    ///     - lateLatencies: Where to put the duration of a late one.
    ///
    /// - Returns: What happened.
    ///
    /// - Throws: Whatever reading the domain raises.
    ///
    private func observe(
        trial: Int,
        from: URL,
        to: URL,
        started: ContinuousClock.Instant,
        note: (Int, String) -> Void,
        into latencies: inout [Duration],
        and lateLatencies: inout [Duration]
    ) async throws -> Outcome {
        do {
            try await Waiter.waitUntilBlocking("trial \(trial) reaches the client", timeout: LiveEnvironment.scaled(Self.trialTimeout)) {
                try LocalNode.at(to) != nil && LocalNode.at(from) == nil
            }

            let took = ContinuousClock.now - started

            latencies.append(took)
            note(trial, "moved, after \(took)")

            return .moved
        } catch {
            // Not yet a loss. Watching on is what separates a move which never arrives from one which is merely slow, and the two are different defects.
            do {
                try await Waiter.waitUntilBlocking("trial \(trial) reaches the client late", timeout: LiveEnvironment.scaled(Self.graceTimeout)) {
                    try LocalNode.at(to) != nil && LocalNode.at(from) == nil
                }

                let arrived = ContinuousClock.now - started

                lateLatencies.append(arrived)
                note(trial, "moved LATE, after \(arrived)")

                return .late
            } catch {
                // Which half of the conjunction never came true, asked once at the end rather than inferred from the timeout.
                let atDestination = (try? LocalNode.at(to)) ?? nil

                guard atDestination == nil else {
                    note(trial, "COPIED: the item reached its destination and was left at its source as well")

                    return .copied
                }

                note(trial, "NOT reached within \(LiveEnvironment.scaled(Self.graceTimeout)), so it is counted as lost")

                return .lost
            }
        }
    }

    ///
    /// Say what the trials came to, in the terminal and in the run's artifacts.
    ///
    /// Attached as well as printed, for the reason this project has had to learn twice: a measurement which reaches only a terminal cannot be compared with the next run's, and comparing runs is the entire purpose of measuring a rate.
    ///
    /// - Parameters:
    ///     - counts: How many trials ended each way.
    ///     - counted: How many were counted at all.
    ///     - dropped: How many were dropped before measuring.
    ///     - latencies: The durations of the on-time arrivals.
    ///     - lateLatencies: The durations of the late ones.
    ///     - cell: What was measured.
    ///     - room: The room it was measured in.
    ///     - underTest: The server it ran against.
    ///
    private func report(
        _ counts: [Outcome: Int],
        counted: Int,
        dropped: Int,
        latencies: [Duration],
        lateLatencies: [Duration],
        for cell: Scenario,
        in room: CleanRoom,
        against underTest: ServerUnderTest
    ) {
        let moved = counts[.moved] ?? 0
        let percentage = Double(moved) / Double(counted) * 100
        let slowest = latencies.max().map { "\($0)" } ?? "—"
        let slowestLate = lateLatencies.max().map { "\($0)" } ?? "—"

        let summary = """
        \(moved) of \(counted) moves reached \(underTest) within \(LiveEnvironment.scaled(Self.trialTimeout)) (\(String(format: "%.0f", percentage))%). \
        \(counts[.late] ?? 0) arrived late, the slowest after \(slowestLate); \
        \(counts[.copied] ?? 0) arrived while the original stayed where it was; \
        \(counts[.lost] ?? 0) never arrived within a further \(LiveEnvironment.scaled(Self.graceTimeout)). \
        \(dropped) trial\(dropped == 1 ? "" : "s") dropped before measuring, slowest on-time arrival \(slowest). \
        Rates hold within one room and one client session rather than across fresh ones
        """

        print("""
          rate: \(cell.description)
                \(summary)
        """)

        ScenarioOracle.observe(summary, in: room)

        for duration in latencies {
            MetricsRecorder.record("server to client move, propagated", duration: duration, in: room, test: cell.description)
        }

        for duration in lateLatencies {
            MetricsRecorder.record("server to client move, late", duration: duration, in: room, test: cell.description)
        }
    }
}
