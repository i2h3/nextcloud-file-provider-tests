// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item made on the server, and whether the client learns of it.
///
/// The mirror of ``LocalCreateTests``, and the harder direction. A client-side create is one request the provider is asked to carry; a server-side create is something nobody told the client about, which it has to notice.
///
/// Three of the nine cells put the new item into a container the client has never listed. That case is the one worth the suite: a client which only learns about new items in folders it has already enumerated would pass every materialized cell and fail these — and a person would find that a file a colleague added never appeared in a folder they had not opened. Because the container must stay unentered, the item is awaited by looking its path up rather than by listing what it is in, which is the same assumption ``ScenarioWorld`` rests its dataless cells on and asserts immediately afterwards.
///
@Suite("Remote create", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct RemoteCreateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .remote, operation: .create), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item created on the server appears in the client, with the content the server holds.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The container state to establish and the kind of item to create in it.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item created on the server appears in the client with its content.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .parent(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the container the item is created in")
        }

        try await CleanRoom.with(underTest, testName: "RemoteCreate.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let name = ScenarioWorld.name("arriving", for: cell.item.kind)
            let site = try await ScenarioWorld.prepareCreation(cell, in: room)
            let url = room.localURL(of: site.localPath(of: name))

            let started = ContinuousClock.now

            try await ScenarioWorld.createItem(cell, named: name, at: site.parentRemotePath, in: room)

            // Awaited by lookup rather than by listing, in every cell rather than only in the dataless ones. Half of them forbid entering the container, and a wait which listed it would establish the opposite precondition and then pass; using the same wait throughout means the cells differ only in what they claim, not in how they are watched.
            try await Waiter.waitUntilBlocking("\"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try LocalNode.at(url) != nil
            }

            MetricsRecorder.record("server to client creation", duration: ContinuousClock.now - started, in: room, test: cell.description)

            if level == .dataless {
                #expect(!room.ledger.hasEnumerated(room.localURL(of: site.parentLocalPath)), """
                Waiting for "\(name)" entered "\(site.parentLocalPath)", so this cell measured a materialized container while claiming a dataless one.
                """)
            }

            let node = try #require(try LocalNode.at(url), "\"\(name)\" was found and then could not be read back.")

            #expect(node.kind == (cell.item.kind == .file ? .file : .directory), """
            "\(name)" arrived in the client as \(node.kind) where a \(cell.item.kind.rawValue) was created on the server.
            """)

            switch cell.item.kind {
                case .file:
                    // Compared against what the server holds rather than against the bytes the fixture was built from, so that the assertion stays true to its name if the fixture ever changes. Materializing the item is a change of its state, and is allowed here: the cell pins the container, and the item's own realization is what this suite declines to judge.
                    let arrived = try Materialization.materialize(url)
                    let stored = try await room.remoteFingerprint(of: site.remotePath(of: name))

                    #expect(ContentFactory.fingerprint(of: arrived) == stored, """
                    "\(name)" reads in the client as different bytes from the ones the server holds.
                    """)

                case .folderWithChildren:
                    // Awaited for the same reason the client-to-server direction awaits it: the folder arriving says nothing about what is inside it yet, and a listing read the moment the folder appears finds an empty one.
                    do {
                        try await Waiter.waitUntilBlocking("the file inside \"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                            try room.localChildren(of: site.localPath(of: name)).contains { $0.name == ScenarioWorld.childFixtureName }
                        }
                    } catch is WaitTimeoutError {
                        let children = try room.localChildren(of: site.localPath(of: name))

                        Issue.record("""
                        The folder arrived without the file inside it, so a person who opens it finds it empty. It holds: \(children.map(\.name).sorted().joined(separator: ", ")).
                        """)
                    }

                case .folderEmpty, .bundle:
                    break
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.createdItemReason)
        }
    }
}
