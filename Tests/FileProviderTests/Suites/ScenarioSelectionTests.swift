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
    /// Twelve of the quadrant's thirty-eight: two realization levels, three kinds of item, two locations. The other twenty-six are excluded by named blockers rather than by oversight — packages, evicted items, deep materialization, filename encodings — and each is a primitive whose absence is countable.
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
            "remote metadataUpdate item:evicted kind:file size:small at:standard:root",
            "remote metadataUpdate item:evicted kind:file size:small at:standard:subdirectory",
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
        #expect(all.count - RemoteMetadataUpdateTests.cells.count == 6, """
        Twenty-six cells of this quadrant are not run. They are blocked on primitives this harness does not have — a package fixture, an observation which separates an evicted item from a placeholder, a recursive materialization walk, a reader for the local-name bounce attribute — and not on anything about the client.
        """)
    }

    ///
    /// Exactly which cells of the remote-delete quadrant this harness runs today.
    ///
    /// Twenty-four of fifty-two. The trash axis is no longer a blocker — the application is turned off and on per room — so what remains is the realization and item-kind blockers which apply everywhere.
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
            "remote delete item:evicted kind:file size:small at:standard:root trash:with",
            "remote delete item:evicted kind:file size:small at:standard:root trash:without",
            "remote delete item:evicted kind:file size:small at:standard:subdirectory trash:with",
            "remote delete item:evicted kind:file size:small at:standard:subdirectory trash:without",
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
        // 328 until a container's realization level stopped being judged against the item's kind, then 350. The matrix itself then grew from 406 to 466: the root-container rule was written as a whitelist admitting only `materialized`, which also dropped `materializedDeep` — a level neither of the two rules it documents mentions, and not degenerate at a root which holds at least the item under test. Sixty rows in the four quadrants which pin a container, none of them previously counted as unbuildable, because they were never generated at all.
        #expect(buildable.count == 410, """
        The harness can build \(buildable.count) of the \(all.count) cells of phase A. A change to this number is either a primitive gained or coverage lost, and both are worth a deliberate edit here.
        """)
    }

    ///
    /// Every generated suite runs the cells its quadrant offers this harness.
    ///
    /// Asserted together rather than one test per quadrant, because the property that matters is the same for all of them and a reader should be able to see the whole shape at once.
    ///
    /// Both counts are pinned per quadrant. The first four quadrants each offer exactly twelve cells, which read for a while like a rule and is a coincidence of what the blockers happen to prune: a create pins its **container** rather than its item, the container lattice is smaller than the item lattice, and the create quadrants therefore offer nine. A number changing here is either a primitive gained or coverage lost, and both are worth a deliberate edit.
    ///
    /// The four quadrants which pin a container now run every cell they offer. They ran fewer because a container asked to be deeply materialized was judged against the *item's* kind and dropped whenever that item was a file — which is the whole of the difference, and is why the four that moved are exactly the four with a container in their realization.
    ///
    @Test(arguments: [
        ("LocalDelete", LocalDeleteTests.cells, Quadrant(origin: .local, operation: .delete), 52, 40),
        ("LocalMetadataUpdate", LocalMetadataUpdateTests.cells, Quadrant(origin: .local, operation: .metadataUpdate), 26, 20),
        ("LocalMove", LocalMoveTests.cells, Quadrant(origin: .local, operation: .move), 48, 48),
        ("RemoteMove", RemoteMoveTests.cells, Quadrant(origin: .remote, operation: .move), 60, 60),
        ("LocalCreate", LocalCreateTests.cells, Quadrant(origin: .local, operation: .create), 30, 30),
        ("RemoteCreate", RemoteCreateTests.cells, Quadrant(origin: .remote, operation: .create), 42, 42),
        ("LocalContentUpdate", LocalContentUpdateTests.cells, Quadrant(origin: .local, operation: .contentUpdate), 8, 8),
        ("RemoteContentUpdate", RemoteContentUpdateTests.cells, Quadrant(origin: .remote, operation: .contentUpdate), 24, 22),
        ("ConcurrentDelete", ConcurrentDeleteTests.cells, Quadrant(origin: .concurrent, operation: .delete), 52, 40),
        ("ConcurrentMetadataUpdate", ConcurrentMetadataUpdateTests.cells, Quadrant(origin: .concurrent, operation: .metadataUpdate), 26, 20),
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

        #expect(excluded == all.count - 410, """
        \(excluded) of the \(all.count) cells of phase A cannot be built, against 56 when this was written — a number which did not move when the matrix grew by sixty, because every one of those sixty is buildable. The breakdown is printed above; a change here is either a primitive gained or coverage lost.
        """)

        #expect(!counts.keys.contains { $0.hasPrefix("a container which is not standard") }, """
        A cell was excluded for its container type, which phase A cannot emit: every placement it offers is a standard container. Either the model changed or this filter is now describing something else.
        """)
    }
}
