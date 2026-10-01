// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ScenarioMatrix
import Testing

///
/// What the generated suites actually run, pinned so that it cannot change quietly.
///
/// Needs no server and no client, and runs under a bare `swift test` like the rest of the hermetic suite. It exists because a generated suite has a failure mode a hand-written one does not: the set of cases can shrink to nothing without a single test failing. A filter that stops matching, an axis value renamed in the model, a constraint that prunes more than it did — each leaves a green run covering less than the run before it, and nothing says so.
///
/// So the count and the rows are asserted here. A change to either is then a deliberate edit to this file with a diff to read, which is the same reason the model keeps a snapshot of its own output.
///
@Suite("Scenario selection")
struct ScenarioSelectionTests {
    ///
    /// Exactly which cells of the remote-metadata-update quadrant this harness runs today.
    ///
    /// Thirty-six of the quadrant's thirty-eight. The two held back are the evicted empty folder, which is not a state to establish but the absence of one: a folder with nothing in it has nothing to drop, so evicted and materialized are the same thing to look at.
    ///
    /// It read twelve of thirty-eight for a long time after it was twenty-four and then thirty-six, which is the drift this file exists to prevent — in the file that exists to prevent it. The counts in the assertions moved each time because they are asserted; this sentence did not, because it is a sentence. Numbers belong in the expectations below, and this paragraph should say what the remainder *is* rather than how many of it there are.
    ///
    @Test
    func `The remote metadata update suite runs the cells it is meant to.`() {
        let expected = [
            "remote metadataUpdate item:dataless kind:bundle at:standard:root",
            "remote metadataUpdate item:dataless kind:bundle at:standard:root enc:caseCollision",
            "remote metadataUpdate item:dataless kind:bundle at:standard:root enc:nfc",
            "remote metadataUpdate item:dataless kind:bundle at:standard:root enc:nfd",
            "remote metadataUpdate item:dataless kind:bundle at:standard:subdirectory",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:caseCollision",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:nfc",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:nfd",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:subdirectory",
            "remote metadataUpdate item:dataless kind:folderEmpty at:standard:root",
            "remote metadataUpdate item:dataless kind:folderEmpty at:standard:root enc:caseCollision",
            "remote metadataUpdate item:dataless kind:folderEmpty at:standard:root enc:nfc",
            "remote metadataUpdate item:dataless kind:folderEmpty at:standard:root enc:nfd",
            "remote metadataUpdate item:dataless kind:folderEmpty at:standard:subdirectory",
            "remote metadataUpdate item:dataless kind:folderWithChildren at:standard:root",
            "remote metadataUpdate item:dataless kind:folderWithChildren at:standard:root enc:caseCollision",
            "remote metadataUpdate item:dataless kind:folderWithChildren at:standard:root enc:nfc",
            "remote metadataUpdate item:dataless kind:folderWithChildren at:standard:root enc:nfd",
            "remote metadataUpdate item:dataless kind:folderWithChildren at:standard:subdirectory",
            "remote metadataUpdate item:evicted kind:bundle at:standard:root",
            "remote metadataUpdate item:evicted kind:bundle at:standard:subdirectory",
            "remote metadataUpdate item:evicted kind:file size:small at:standard:root",
            "remote metadataUpdate item:evicted kind:file size:small at:standard:subdirectory",
            "remote metadataUpdate item:evicted kind:folderWithChildren at:standard:root",
            "remote metadataUpdate item:evicted kind:folderWithChildren at:standard:subdirectory",
            "remote metadataUpdate item:materialized kind:bundle at:standard:root",
            "remote metadataUpdate item:materialized kind:bundle at:standard:subdirectory",
            "remote metadataUpdate item:materialized kind:file size:small at:standard:root",
            "remote metadataUpdate item:materialized kind:file size:small at:standard:subdirectory",
            "remote metadataUpdate item:materialized kind:folderEmpty at:standard:root",
            "remote metadataUpdate item:materialized kind:folderEmpty at:standard:subdirectory",
            "remote metadataUpdate item:materialized kind:folderWithChildren at:standard:root",
            "remote metadataUpdate item:materialized kind:folderWithChildren at:standard:subdirectory",
            "remote metadataUpdate item:materializedDeep kind:folderWithChildren at:standard:root",
            "remote metadataUpdate item:materializedDeep kind:folderWithChildren at:standard:subdirectory",
        ]

        #expect(RemoteMetadataUpdateTests.cells.map(\.description) == expected, """
        The set of cells this suite runs is not the set it was written against. Either the model changed, or the filter stopped matching what it used to — and a generated suite can quietly run fewer cases, or none, without any test failing.
        """)
    }

    ///
    /// The quadrant is bigger than what runs, and the difference is the work not yet done.
    ///
    /// Asserted rather than commented so that building one of the missing primitives shows up here as a number moving, rather than as nothing at all.
    ///
    @Test
    func `The cells not yet run are counted rather than forgotten.`() {
        let all = Generator.scenarios(for: Quadrant(origin: .remote, operation: .metadataUpdate), phase: .a)

        #expect(all.count == 38)
        #expect(all.count - RemoteMetadataUpdateTests.cells.count == 2, """
        Two cells of this quadrant are not run, both asking for an evicted empty folder — a state with nothing in it to drop, so nothing distinguishes it from a materialized one. Every other primitive this quadrant was once blocked on has been built.
        """)
    }

    ///
    /// Exactly which cells of the remote-delete quadrant this harness runs today.
    ///
    /// Forty-eight of fifty-two. The trash axis is no longer a blocker — the application is turned off and on per room — so what remains is the evicted empty folder, which is excluded for being indistinguishable from a materialized one rather than for being hard to build.
    ///
    @Test
    func `The remote delete suite runs the cells it is meant to.`() {
        let expected = [
            "remote delete item:dataless kind:bundle at:standard:root trash:with",
            "remote delete item:dataless kind:bundle at:standard:root trash:without",
            "remote delete item:dataless kind:bundle at:standard:subdirectory trash:with",
            "remote delete item:dataless kind:bundle at:standard:subdirectory trash:without",
            "remote delete item:dataless kind:file size:small at:standard:root trash:with",
            "remote delete item:dataless kind:file size:small at:standard:root trash:without",
            "remote delete item:dataless kind:file size:small at:standard:subdirectory trash:with",
            "remote delete item:dataless kind:file size:small at:standard:subdirectory trash:without",
            "remote delete item:dataless kind:folderEmpty at:standard:root trash:with",
            "remote delete item:dataless kind:folderEmpty at:standard:root trash:without",
            "remote delete item:dataless kind:folderEmpty at:standard:subdirectory trash:with",
            "remote delete item:dataless kind:folderEmpty at:standard:subdirectory trash:without",
            "remote delete item:dataless kind:folderWithChildren at:standard:root trash:with",
            "remote delete item:dataless kind:folderWithChildren at:standard:root trash:without",
            "remote delete item:dataless kind:folderWithChildren at:standard:subdirectory trash:with",
            "remote delete item:dataless kind:folderWithChildren at:standard:subdirectory trash:without",
            "remote delete item:evicted kind:bundle at:standard:root trash:with",
            "remote delete item:evicted kind:bundle at:standard:root trash:without",
            "remote delete item:evicted kind:bundle at:standard:subdirectory trash:with",
            "remote delete item:evicted kind:bundle at:standard:subdirectory trash:without",
            "remote delete item:evicted kind:file size:small at:standard:root trash:with",
            "remote delete item:evicted kind:file size:small at:standard:root trash:without",
            "remote delete item:evicted kind:file size:small at:standard:subdirectory trash:with",
            "remote delete item:evicted kind:file size:small at:standard:subdirectory trash:without",
            "remote delete item:evicted kind:folderWithChildren at:standard:root trash:with",
            "remote delete item:evicted kind:folderWithChildren at:standard:root trash:without",
            "remote delete item:evicted kind:folderWithChildren at:standard:subdirectory trash:with",
            "remote delete item:evicted kind:folderWithChildren at:standard:subdirectory trash:without",
            "remote delete item:materialized kind:bundle at:standard:root trash:with",
            "remote delete item:materialized kind:bundle at:standard:root trash:without",
            "remote delete item:materialized kind:bundle at:standard:subdirectory trash:with",
            "remote delete item:materialized kind:bundle at:standard:subdirectory trash:without",
            "remote delete item:materialized kind:file size:small at:standard:root trash:with",
            "remote delete item:materialized kind:file size:small at:standard:root trash:without",
            "remote delete item:materialized kind:file size:small at:standard:subdirectory trash:with",
            "remote delete item:materialized kind:file size:small at:standard:subdirectory trash:without",
            "remote delete item:materialized kind:folderEmpty at:standard:root trash:with",
            "remote delete item:materialized kind:folderEmpty at:standard:root trash:without",
            "remote delete item:materialized kind:folderEmpty at:standard:subdirectory trash:with",
            "remote delete item:materialized kind:folderEmpty at:standard:subdirectory trash:without",
            "remote delete item:materialized kind:folderWithChildren at:standard:root trash:with",
            "remote delete item:materialized kind:folderWithChildren at:standard:root trash:without",
            "remote delete item:materialized kind:folderWithChildren at:standard:subdirectory trash:with",
            "remote delete item:materialized kind:folderWithChildren at:standard:subdirectory trash:without",
            "remote delete item:materializedDeep kind:folderWithChildren at:standard:root trash:with",
            "remote delete item:materializedDeep kind:folderWithChildren at:standard:root trash:without",
            "remote delete item:materializedDeep kind:folderWithChildren at:standard:subdirectory trash:with",
            "remote delete item:materializedDeep kind:folderWithChildren at:standard:subdirectory trash:without",
        ]

        #expect(RemoteDeleteTests.cells.map(\.description) == expected, """
        The set of cells this suite runs is not the set it was written against. Either the model changed, or the shared filter stopped matching what it used to — and a generated suite can quietly run fewer cases, or none, without any test failing.
        """)
    }

    ///
    /// What the whole matrix offers against what this harness can take, counted in one place.
    ///
    /// The single number that says how far adoption has got. It is asserted rather than printed so that building a primitive is visible as this number moving, and so that a change to the model which silently prunes rows cannot pass unnoticed.
    ///
    @Test
    func `The share of the matrix this harness can run is counted rather than estimated.`() {
        let all = Generator.matrix(for: .a).values.flatMap(\.self)
        let buildable = all.filter(ScenarioSelection.isBuildable)

        #expect(all.count == 466)
        // 328 until a container's realization level stopped being judged against the item's kind, then 350. The matrix itself then grew from 406 to 466: the root-container rule was written as a whitelist admitting only `materialized`, which also dropped `materializedDeep` — a level neither of the two rules it documents mentions, and not degenerate at a root which holds at least the item under test. Sixty rows in the four quadrants which pin a container, none of them previously counted as unbuildable, because they were never generated at all. Then 448: a probe measured that a directory can be evicted after all — the system accepts it, the children come back with no allocated blocks, and only the folder's own flag stays clear — so thirty-eight of the fifty-six cells refused for it are refused no longer. An empty folder still is, and now for a reason which is about the state rather than about the mechanism: it holds nothing to drop, so evicted and materialized are the same thing to look at.
        #expect(buildable.count == 448, """
        The harness can build \(buildable.count) of the \(all.count) cells of phase A. A change to this number is either a primitive gained or coverage lost, and both are worth a deliberate edit here.
        """)
    }

    ///
    /// Every generated suite runs the cells its quadrant offers this harness.
    ///
    /// Asserted together rather than one test per quadrant, because the property that matters is the same for all of them and a reader should be able to see the whole shape at once.
    ///
    /// Both counts are pinned per quadrant, in the arguments below, and deliberately nowhere else. A number changing there is either a primitive gained or coverage lost, and both are worth a deliberate edit with a diff to read.
    ///
    /// This paragraph used to carry the numbers as well, and carried them long after they had moved — twelve apiece for the first four quadrants, nine for the creates, against a table reading fifty-two, twenty-six, forty-eight and sixty. A count written twice is a count that disagrees with itself eventually, and the copy nothing asserts is the one that drifts.
    ///
    /// The four quadrants which pin a container now run every cell they offer. They ran fewer because a container asked to be deeply materialized was judged against the *item's* kind and dropped whenever that item was a file — which is the whole of the difference, and is why the four that moved are exactly the four with a container in their realization.
    ///
    @Test(arguments: [
        ("LocalDelete", LocalDeleteTests.cells, Quadrant(origin: .local, operation: .delete), 52, 48),
        ("LocalMetadataUpdate", LocalMetadataUpdateTests.cells, Quadrant(origin: .local, operation: .metadataUpdate), 26, 24),
        ("LocalMove", LocalMoveTests.cells, Quadrant(origin: .local, operation: .move), 48, 48),
        ("RemoteMove", RemoteMoveTests.cells, Quadrant(origin: .remote, operation: .move), 60, 60),
        ("LocalCreate", LocalCreateTests.cells, Quadrant(origin: .local, operation: .create), 30, 30),
        ("RemoteCreate", RemoteCreateTests.cells, Quadrant(origin: .remote, operation: .create), 42, 42),
        ("LocalContentUpdate", LocalContentUpdateTests.cells, Quadrant(origin: .local, operation: .contentUpdate), 8, 8),
        ("RemoteContentUpdate", RemoteContentUpdateTests.cells, Quadrant(origin: .remote, operation: .contentUpdate), 24, 24),
        ("ConcurrentDelete", ConcurrentDeleteTests.cells, Quadrant(origin: .concurrent, operation: .delete), 52, 48),
        ("ConcurrentMetadataUpdate", ConcurrentMetadataUpdateTests.cells, Quadrant(origin: .concurrent, operation: .metadataUpdate), 26, 24),
        ("ConcurrentContentUpdate", ConcurrentContentUpdateTests.cells, Quadrant(origin: .concurrent, operation: .contentUpdate), 8, 8),
    ] as [(String, [Scenario], Quadrant, Int, Int)])
    func `Each generated quadrant runs the cells it is meant to.`(_ quadrant: (name: String, cells: [Scenario], quadrant: Quadrant, total: Int, running: Int)) {
        let all = Generator.scenarios(for: quadrant.quadrant, phase: .a)

        #expect(all.count == quadrant.total, "\(quadrant.name) offers \(all.count) cells where it offered \(quadrant.total).")
        #expect(quadrant.cells.count == quadrant.running, "\(quadrant.name) runs \(quadrant.cells.count) cells where it ran \(quadrant.running).")

        #expect(quadrant.cells == ScenarioSelection.cells(of: quadrant.quadrant), """
        \(quadrant.name) runs a different set of cells from what the shared filter selects, which means the suite has its own filter and the two can drift apart.
        """)
    }

    ///
    /// Why each cell this harness cannot run is one it cannot run, counted by cause.
    ///
    /// The total alone is a number nobody can act on. It was carried for weeks as "sharing and group folders", which phase A does not offer at all — every placement it emits is a standard container — so the real reasons went unexamined until something made them print themselves. Counted by cause, the remainder stops being a backlog and becomes a list: each line is one primitive, and building it moves a number here.
    ///
    /// Printed as well as asserted, because the breakdown is the useful half and a test which only compares totals says nothing about what changed.
    ///
    @Test
    func `Every cell the harness cannot run names the reason, and the reasons are counted.`() {
        let all = Generator.matrix(for: .a).values.flatMap(\.self)
        var counts = [String: Int]()

        for scenario in all {
            guard let blocker = ScenarioSelection.blocker(for: scenario) else {
                continue
            }

            counts[blocker, default: 0] += 1
        }

        let excluded = counts.values.reduce(0, +)

        for (reason, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("  unbuildable: \(count) cell\(count == 1 ? "" : "s") ask for \(reason)")
        }

        #expect(excluded == all.count - 448, """
        \(excluded) of the \(all.count) cells of phase A cannot be built, against 56 when this was written — a number which did not move when the matrix grew by sixty, because every one of those sixty is buildable. The breakdown is printed above; a change here is either a primitive gained or coverage lost.
        """)

        #expect(!counts.keys.contains { $0.hasPrefix("a container which is not standard") }, """
        A cell was excluded for its container type, which phase A cannot emit: every placement it offers is a standard container. Either the model changed or this filter is now describing something else.
        """)

        // Asked separately, because the clause above cannot answer it. A read-only *standard* container is standard, so it satisfies the type check and would slip past that assertion into a harness which builds a writable folder and finds the convergence the cell was written to see refused.
        //
        // Phase A cannot emit one today: ``ScenarioMatrix/ContainerProfile/init(type:permission:)`` refuses the pairing. That refusal is a harness claim living in the model, and it is the sort of thing that gets corrected — so the day it is, this line is what says so, rather than a hundred and fifty-six cells quietly passing.
        #expect(!counts.keys.contains { $0.hasPrefix("a container which rejects writes") }, """
        A cell was excluded for rejecting writes, which phase A cannot emit: every container it offers is read-write. The model has started describing refusals, and nothing in this harness observes one — see ScenarioSelection and ScenarioWorld, which now hold such cells back by name.
        """)
    }

    ///
    /// How many cells run expecting to fail, counted by quadrant.
    ///
    /// The same argument as every other count in this file, applied to the one set it did not cover. ``KnownLimitation`` paints a cell's failure as expected, and the size of that set is coverage: a cell painted expected is a cell whose verdict this suite has stopped reading. Nothing asserted it, and the repository said so twice in prose — ninety-three in ``KnownLimitation`` and twenty-seven in ``CleanRoom`` — against the number this test measures. Two stale sentences and no test is exactly the shape ``ScenarioSelectionTests`` exists to rule out.
    ///
    /// ``KnownLimitation/reason(for:)`` matches on a cell's description, so the set moves whenever the model's spelling does. Renaming an axis value narrows it to nothing and the painted cells start failing for real, which is loud; dropping one of its two carve-outs widens it over cells which pass today, and `withKnownIssue` answers that with *expected issue did not occur*, which is also loud. What is **not** loud is the size drifting while both ends still behave — a kind gaining a value, a quadrant gaining rows — and that is what the number below is for.
    ///
    /// Printed by quadrant rather than asserted per quadrant. The breakdown is what a reader acts on, and pinning thirteen numbers would make every matrix change a thirteen-line diff for no more safety than one line gives.
    ///
    @Test
    func `The cells which run expecting to fail are counted rather than described.`() {
        let buildable = Generator.matrix(for: .a).values.flatMap(\.self).filter(ScenarioSelection.isBuildable)
        var counts = [String: Int]()

        for scenario in buildable where KnownLimitation.reason(for: scenario.description) != nil {
            counts["\(scenario.origin.rawValue) \(scenario.operation.rawValue)", default: 0] += 1
        }

        let limited = counts.values.reduce(0, +)

        for (quadrant, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("  known limitation: \(count) cell\(count == 1 ? "" : "s") in \(quadrant)")
        }

        #expect(limited == 49, """
        \(limited) of the \(buildable.count) buildable cells run expecting to fail, against 49 when this was written. Up is coverage this suite has stopped reading the verdict of; down is the client having gained something, and the entry in KnownLimitation should go with it.
        """)
    }

    ///
    /// The limitation is scoped to what was measured, and nothing wider.
    ///
    /// Both carve-outs were cut by a run contradicting the rule, which is the argument for running these cells rather than excluding them, made twice by the suite itself. They are asserted here because they are the difference between a registered limitation and a blanket suppression: without them the rule would paint every bundle cell, including the fifty which pass today, and a real regression in any of them would be read as the packages refusal.
    ///
    @Test
    func `A cell the client is known to handle is not painted as a limitation.`() {
        let buildable = Generator.matrix(for: .a).values.flatMap(\.self).filter(ScenarioSelection.isBuildable)
        let bundles = buildable.filter { $0.item.kind == .bundle }

        #expect(bundles.count == 107, "The model offers \(bundles.count) buildable bundle cells where it offered 107, so the share this rule reaches has moved.")

        for cell in bundles where cell.origin == .remote {
            #expect(KnownLimitation.reason(for: cell.description) == nil, """
            "\(cell.description)" is painted as a known limitation, but a package created on the server reaches the client — five cells said so by failing the expectation rather than the cell.
            """)
        }

        for cell in bundles where cell.operation == .delete && cell.description.contains("item:dataless") {
            #expect(KnownLimitation.reason(for: cell.description) == nil, """
            "\(cell.description)" is painted as a known limitation, but deleting a package the client never downloaded reaches the server like any other deletion.
            """)
        }
    }
}
