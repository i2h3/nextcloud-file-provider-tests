// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// How often a deletion of a placeholder reaches the server.
///
/// Not a contract test. ``LocalDeleteTests`` already asserts that deleting an item in the client deletes it on the server, and it fails when that does not happen — but it runs each cell once, and the thing it found does not happen every time. Two runs of twelve cells produced five failures, all of them on items whose content had never been downloaded, none of them on materialized items, and not the same cells twice. That is enough to know the defect is real and confined to placeholders, and not enough to know anything else.
///
/// So this measures. It performs the same deletion many times and reports the proportion that reached the server, which is the number a bug report needs and the number a fix has to move.
///
/// ## What it is careful about
///
/// **It asserts almost nothing.** A characterisation suite which fails is a characterisation suite nobody runs twice, and the failure is already asserted elsewhere. The only expectation here is that the deletion happened locally — because a trial where the item never left the disk is not a sample of anything, and counting it as a failure to propagate would inflate the very rate being measured.
///
/// **Trials share a room, and that is the limitation to read every number here through.** Building a clean room takes about eighty seconds against a trial's three, so a room per trial puts a hundred samples out of reach. The cost is that trials are not independent: they run against one account, one domain and one client which has been running for a while.
///
/// How much that costs was learned the hard way. A first version also left the item on the server after a failed trial, which meant each trial started from a state its predecessors had produced — and the numbers that came out described a room degrading rather than a defect recurring. A failed trial now restores the server, which removes the debris but not the client's memory of it, so these remain rates **within one session**, and a cell which fails repeatedly may be reporting one bad state rather than many independent failures.
///
/// **A trial that cannot be set up is dropped rather than counted.** Establishing the placeholder can itself fail, and those trials say nothing about deletion either way.
///
@Suite("Deletion propagation rate", .requiresLiveEnvironment, .requiresRepetitions, .serialized, .timeLimit(.minutes(60)))
struct DeletionPropagationRateTests {
    ///
    /// How long a single trial waits for the server before calling it a failure.
    ///
    /// Far shorter than the contract suite's three minutes, and deliberately. Across eighty-four successful deletions measured so far the slowest took 3.04 seconds and none came close to twice that, so ten seconds is more than three times the observed worst case while keeping a run of several hundred trials to a sensible length.
    ///
    /// The length matters more than it looks, because it is paid by the failures rather than the successes: a trial which propagates finishes in about two seconds, and a trial which does not costs the whole timeout. At a quarter of trials failing, the timeout is most of the running time of this suite.
    ///
    /// A deletion which would have arrived at twelve seconds is not counted as lost, but as late: ``graceTimeout`` keeps watching after this expires. The slowest success is still reported beside the rate, because a distribution creeping towards this limit means the fast number is measuring the timeout rather than the client.
    ///
    static let trialTimeout = Duration.seconds(10)

    ///
    /// How long a trial keeps watching after it has already been counted as not propagating.
    ///
    /// The distinction this exists for is the one the suite was silently unable to make. A deletion which never reaches the server is a permanent divergence and silent data retention; a deletion which reaches it at forty seconds is a delay. They are different defects, they live in different code, and a bug report which confuses them sends a maintainer to the wrong half of the client.
    ///
    /// Until this existed the suite could not tell them apart *and destroyed the evidence*: a failed trial restored the server immediately, which removed the only thing a late arrival could have been observed in. Every "lost" deletion measured before this was really "not within ten seconds", and nothing more.
    ///
    /// Long enough to cover the thirty-second poll interval twice over, since a client which missed a push and falls back to polling is the obvious candidate for an arrival which is late rather than absent.
    ///
    static let graceTimeout = Duration.seconds(90)

    ///
    /// The cells whose behaviour is being measured.
    ///
    /// Every buildable local deletion of an item which is a placeholder. The materialized cells are deliberately included as a control: they have not failed once in twenty-four attempts, and a run where they start failing is measuring something other than what this suite thinks it is.
    ///
    ///
    /// One cell run under one arm, which is what a case of this suite actually is.
    ///
    /// A pair rather than two argument lists, because the testing library takes at most two collections and the server is one of them. Pairing them here also lets the impossible combinations be left out rather than returned from early, so the count of cases is the count of measurements.
    ///
    struct Trial: Sendable, CustomStringConvertible, CustomTestArgumentEncodable {
        ///
        /// The state to establish and delete.
        ///
        let cell: Scenario

        ///
        /// What to do to the item before deleting it.
        ///
        let arm: Arm

        ///
        /// How the pair names itself in a run.
        ///
        var description: String {
            "\(cell.description) [\(arm.rawValue)]"
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
    /// Every pairing worth running.
    ///
    /// The extra arm is generated only where it says something: a cell which already fetches the item cannot be told apart from itself, and only a file can be fetched and evicted.
    ///
    static let trials: [Trial] = LocalDeleteTests.cells.flatMap { cell -> [Trial] in
        guard case let .item(level) = cell.realization else {
            return []
        }

        guard level == .dataless else {
            return [Trial(cell: cell, arm: .asSpecified)]
        }

        switch cell.item.kind {
            case .file: return [Trial(cell: cell, arm: .asSpecified), Trial(cell: cell, arm: .fetchedThenEvicted)]
            case .folderWithChildren: return [Trial(cell: cell, arm: .asSpecified), Trial(cell: cell, arm: .listedNotFetched)]
            default: return [Trial(cell: cell, arm: .asSpecified)]
        }
    }

    ///
    /// Whether a trial should fetch the item's content through the provider before deleting it, even though the cell does not ask for it.
    ///
    /// The third arm, and the one that decides what the defect actually is.
    ///
    /// Two arms are not enough to name a cause. The materialized arm has never lost a deletion and the dataless arm loses them often, but the two differ in more than one way: a materialized item has its content on disk **and** the harness fetched that content through the provider immediately beforehand, which a dataless item never does. Either could be what protects it, and they point at different code — one at how the client handles items with no local content, the other at what a provider round trip leaves behind in the system's idea of the item.
    ///
    /// So this arm takes a dataless cell, reads the item through the provider, and evicts the content again. What is left has no content on disk, exactly like the dataless arm, and has been through a fetch, exactly like the materialized arm. If deletions stop being lost, the protective factor is the round trip and the claim "placeholders are affected" is wrong. If they keep being lost, content on disk is the axis after all.
    ///
    enum Arm: String, CaseIterable, Sendable {
        ///
        /// The cell as the model describes it, with nothing added.
        ///
        case asSpecified

        ///
        /// A dataless item which was fetched and then evicted, so that it has been through the provider without keeping its content.
        ///
        case fetchedThenEvicted

        ///
        /// A dataless folder which was listed once and whose children were left where they were.
        ///
        /// The same question as ``fetchedThenEvicted`` asks of a file, asked of a folder, because a folder cannot be asked it the same way: content can be evicted and an enumeration cannot be undone, so there is no arm which has listed the folder and then returns it to never having been listed.
        ///
        /// What can be done is to stop halfway. A dataless folder has never been listed and its children have never been fetched; a materialized one has had both. This lists it exactly once and fetches nothing, which separates the two — if deletions stop being lost, what protects the folder is the system having learned what is inside it, and if they keep being lost it is the children's content.
        ///
        case listedNotFetched
    }

    ///
    /// Delete the same kind of item many times and report how often the server heard about it.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and delete, repeatedly.
    ///
    @Test(arguments: LiveEnvironment.servers, trials)
    func `Deleting the same item repeatedly shows how often the deletion reaches the server.`(_ underTest: ServerUnderTest, _ trialCase: Trial) async throws {
        let cell = trialCase.cell
        let arm = trialCase.arm

        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        guard let trials = RunEnvironment.repetitions() else {
            throw ScenarioWorldError.unsupported("a characterisation run, which needs \(RunEnvironment.repetitionsVariableName) set")
        }

        try await CleanRoom.with(underTest, testName: "DeletionPropagationRate.\(cell.item.kind.rawValue).\(level.rawValue).\(arm.rawValue)") { room in
            // Reported while the trials run rather than only after them. A cell is twenty repetitions of something slow, each one building a world and waiting on a server, and a suite which prints nothing for half an hour is indistinguishable from one which has stopped.
            print("  cell: \(cell.description)  [\(arm.rawValue)], \(trials) repetitions")

            func note(_ trial: Int, _ outcome: String) {
                print("        trial \(trial) of \(trials): \(outcome)")
            }

            var reached = 0
            var late = 0
            var lost = 0
            var dropped = 0
            var latencies = [Duration]()
            var lateLatencies = [Duration]()

            for trial in 1 ... trials {
                let name = cell.item.kind == .file ? "trial-\(trial).bin" : "trial-\(trial)"
                let subject: ScenarioSubject

                do {
                    subject = try await ScenarioWorld.build(cell, in: room, named: name)
                } catch {
                    // The world would not build, so this trial is a sample of nothing. Counting it either way would put a fault in the setting up into a number about the client.
                    dropped += 1
                    note(trial, "dropped, because its world would not build: \(error)")

                    continue
                }

                let url = room.localURL(of: subject.localPath(of: name))

                if arm == .listedNotFetched {
                    // One listing and nothing else. `children(of:)` records the enumeration in the room's ledger, which is what the rest of the suite relies on to know that a container was entered, so this arm is visible there rather than being an untracked read behind the ledger's back.
                    _ = try LocalDirectory.children(of: url, ledger: room.ledger)
                }

                if arm == .fetchedThenEvicted {
                    // Through the provider and back out again: the content is fetched and then dropped, leaving an item with no bytes on disk which the provider has nonetheless been asked about.
                    _ = try Materialization.materialize(url)

                    // `evict` reports whether the system accepted the request rather than throwing, and an arm which silently failed to evict would be the materialized arm wearing another name — which is precisely the confusion this arm exists to resolve.
                    guard Materialization.evict(url) else {
                        dropped += 1
                        note(trial, "dropped, because the system would not evict the content it had just fetched")

                        continue
                    }

                    try await Waiter.waitUntilBlocking("trial \(trial) settles as a placeholder again", timeout: LiveEnvironment.scaled(.seconds(30))) {
                        try LocalNode.at(url)?.isDataless == true
                    }
                }

                let started = ContinuousClock.now

                try FileManager.default.removeItem(at: url)

                #expect(try LocalNode.at(url) == nil, "Trial \(trial): removing the item left it on disk, so this trial measures nothing about propagation.")

                do {
                    try await Waiter.poll("trial \(trial) reaches the server", timeout: LiveEnvironment.scaled(Self.trialTimeout)) {
                        try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == name }
                    }

                    let took = ContinuousClock.now - started

                    latencies.append(took)
                    reached += 1
                    note(trial, "reached \(underTest) after \(took)")
                } catch {
                    // Not yet a loss, only an absence at ten seconds. Watching on is what separates a deletion which never arrives from one which is merely slow, and the two are different defects — the first is a permanent divergence the user cannot see, the second is a delay.
                    var arrived: Duration?

                    do {
                        try await Waiter.poll("trial \(trial) reaches the server late", timeout: LiveEnvironment.scaled(Self.graceTimeout)) {
                            try await !room.remoteChildren(of: subject.parentRemotePath).contains { $0.name == name }
                        }

                        arrived = ContinuousClock.now - started
                    } catch {
                        arrived = nil
                    }

                    if let arrived {
                        late += 1
                        lateLatencies.append(arrived)
                        note(trial, "reached \(underTest) LATE, after \(arrived)")

                        continue
                    }

                    lost += 1
                    note(trial, "NOT reached within \(LiveEnvironment.scaled(Self.graceTimeout)), so it is counted as lost")

                    // Put the server back where it started, or the next trial is not a fresh sample of anything.
                    //
                    // The first version left the item in place, reasoning that the accumulating remainder was part of what was being measured. It was not — it was the reason there was nothing to measure. Every failed trial left a file behind, so each trial began from a state its predecessors had produced, and the numbers described how quickly a room degrades rather than how often a deletion is lost. One cell scored twenty out of twenty and another nothing out of twenty in the same run, which is not a rate: at an independent rate of two in three, scoring nothing in twenty attempts has a probability of about one in a billion.
                    //
                    // This is the cheap correction rather than the right one. Independent trials want a room each, and a room costs eighty seconds against a trial's three. Restoring the server removes the debris but not whatever the client has made of it.
                    try? await room.server.delete(subject.remotePath)
                }
            }

            let counted = reached + late + lost

            guard counted > 0 else {
                Issue.record("Every trial of \(cell.description) failed to build, so nothing was measured.")

                return
            }

            let percentage = Double(reached) / Double(counted) * 100
            let slowest = latencies.max().map { "\($0)" } ?? "—"
            let slowestLate = lateLatencies.max().map { "\($0)" } ?? "—"

            print("""
              rate: \(cell.description)  [\(arm.rawValue)]
                    \(reached) of \(counted) deletions reached \(underTest) within \(LiveEnvironment.scaled(Self.trialTimeout)) (\(String(format: "%.0f", percentage))%)
                    \(late) arrived late, the slowest after \(slowestLate); \(lost) never arrived within a further \(LiveEnvironment.scaled(Self.graceTimeout))
                    \(dropped) trial\(dropped == 1 ? "" : "s") dropped before measuring, slowest on-time success \(slowest)
                    rates hold within one room and one client session rather than across fresh ones
            """)
        }
    }
}
