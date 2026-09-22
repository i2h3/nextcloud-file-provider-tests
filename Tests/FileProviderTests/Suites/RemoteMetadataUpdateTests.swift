// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// A rename made on the server, and whether it reaches the client intact.
///
/// The first suite in this project whose cases are **generated rather than written**. Its cases come from the axis model in ``ScenarioMatrix``, which enumerates the states an item can be in and the operations that can be performed on it, and prunes the combinations that cannot exist. One test function stands here; the model decides how many times it runs and with what.
///
/// That is a deliberate change of shape, and the reason is what the suite around it looks like without it. Every other suite in this project varies exactly one thing — which server it talks to — and pins every other dimension to whatever value the person writing the test happened to choose: a file, at the root, already materialized, of one size. Those choices are invisible, so the coverage they leave out is invisible too. Here they are axis values, and what is not covered is a row nobody has enabled yet rather than a question nobody asked.
///
/// This quadrant was chosen to be first because it is the largest thing the suite had never tested at all. A rename on the server is not exercised anywhere else in this project: the only server-originated operation covered until now was creation.
///
/// ## What these cells do not assert
///
/// Five oracle clauses stand on every cell of this quadrant. Three are evaluated. Two are declined by name at the end of each case, because implementing them against what a test process can observe would produce assertions that cannot fail — a green tick per run covering nothing. Which of the two it is is printed rather than left to be discovered.
///
@Suite("Remote metadata update", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct RemoteMetadataUpdateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    /// Generated, then filtered down to what the world builder can actually construct — there is no list of test cases here to fall out of step with the model. A cell excluded by this filter is excluded for a named, countable reason: a package needs a fixture builder, an evicted item needs an observation that separates it from a placeholder, a deep-materialized directory needs a recursive walk. Each of those is a primitive, and building one turns its rows on without anything here changing.
    ///
    static let cells: [Scenario] = ScenarioSelection.cells(of: Quadrant(origin: .remote, operation: .metadataUpdate))

    ///
    /// The contract: a name changed on the server becomes that name on the client, and nothing else about the item changes.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The state to establish and the item to establish it for.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `A name changed on the server becomes that name in the client, and changes nothing else.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .item(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the item")
        }

        try await CleanRoom.with(underTest, testName: "RemoteMetadataUpdate.\(cell.item.kind.rawValue).\(level.rawValue)", cell: cell.description) { room in
            let before = ScenarioWorld.name("before", for: cell.item.kind, encoding: cell.encoding)
            let after = ScenarioWorld.name("after", for: cell.item.kind, encoding: cell.encoding)

            // Everything up to here is world building. A failure in it means this cell was never measured, which is a different thing from the client being wrong, and it is reported as one.
            let subject = try await ScenarioWorld.build(cell, in: room, named: before)

            try await room.server.move(subject.remotePath, to: subject.remotePath(of: after), overwrite: false)

            let started = ContinuousClock.now
            let node = try await ScenarioOracle.awaitRename(of: subject, to: after, in: room, timeout: LiveEnvironment.scaled(.seconds(180)))

            MetricsRecorder.record("server to client rename", duration: ContinuousClock.now - started, in: room, test: cell.description)

            try await ScenarioOracle.checkConsistency(of: subject, renamedTo: after, in: room)
            ScenarioOracle.checkRealizationState(node, scenario: cell, expected: level)
            try await ScenarioOracle.checkIdentityStability(of: subject, renamedTo: after, in: room)
            try await ScenarioOracle.checkContentMatch(of: subject, renamedTo: after, for: cell, in: room)

            // Said once for the run rather than once per case: the reason is the same every time, and a generated suite runs this body a dozen times or more.
            ScenarioOracle.judgeDuplicates(for: cell, named: after, under: subject.parentLocalPath, in: room)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
        }
    }
}
