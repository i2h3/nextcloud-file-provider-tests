// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Testing

///
/// An item made in the client, and whether the server ends up with it.
///
/// The first quadrant whose cells pin a **container** rather than an item, which is what makes it worth having beyond the obvious. Three of its nine cells create into a folder the client has never listed — a folder which exists in the domain as a placeholder and whose contents the system has never asked the provider about. That is the ordinary situation of a person saving a file into a synced folder they have not opened, and it is the one this suite exists for.
///
/// The interesting failure it can catch is not "the file did not arrive". It is a file which arrives while the container it went into is quietly enumerated on the way, because then every later cell claiming a dataless container is measuring a materialized one. The enumeration ledger is asserted for exactly that reason, and it can only see what this test itself did — which is why nothing in this body lists the container.
///
@Suite("Local create", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(60)))
struct LocalCreateTests {
    ///
    /// The cells of this quadrant which this harness can currently establish and judge.
    ///
    static let cells: [Scenario] = Generator
        .scenarios(for: Quadrant(origin: .local, operation: .create), phase: .a)
        .filter(ScenarioSelection.isBuildable)
        .sorted { $0.description < $1.description }

    ///
    /// The contract: an item created in the client reaches the server with the content it was given.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - cell: The container state to establish and the kind of item to create in it.
    ///
    @Test(arguments: LiveEnvironment.servers, cells)
    func `An item created in the client reaches the server with its content.`(_ underTest: ServerUnderTest, _ cell: Scenario) async throws {
        guard case let .parent(level) = cell.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the container the item is created in")
        }

        try await CleanRoom.with(underTest, testName: "LocalCreate.\(cell.item.kind.rawValue).\(level.rawValue)") { room in
            let name = ScenarioWorld.name("fresh", for: cell.item.kind)
            let site = try await ScenarioWorld.prepareCreation(cell, in: room)
            let url = room.localURL(of: site.localPath(of: name))
            // The cell's size rather than one size for every cell. A cell asking for an empty file and given sixty-four kilobytes would claim to test "nothing to upload" while testing the opposite.
            guard let size = ScenarioWorld.bytes(for: cell.item.size) else {
                throw ScenarioWorldError.unsupported("a file of size \(cell.item.size?.rawValue ?? "unspecified"), which the shared filter excludes")
            }

            let content = ContentFactory.content(size: size, seed: 81)
            let childContent = ContentFactory.content(size: ScenarioWorld.smallFileSize, seed: 82)

            let started = ContinuousClock.now

            switch cell.item.kind {
                case .file:
                    try content.write(to: url)

                case .folderEmpty:
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

                case .folderWithChildren:
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                    try childContent.write(to: url.appending(path: ScenarioWorld.childFixtureName, directoryHint: .notDirectory))

                case .bundle:
                    // Made exactly as a folder with a file in it is made, because that is what it is. The Finder shows one item and the server stores a tree, and the disagreement between those two views is what these cells exist to test.
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                    try content.write(to: url.appending(path: ScenarioWorld.bundleContentName, directoryHint: .notDirectory))
            }

            // Asserted immediately, while the only thing that has touched the domain is the write above. A create resolves its parent to place the new item there, and whether that resolution enumerates the container is the assumption every dataless cell in this suite rests on. If it does, this cell established a materialized container and claimed a dataless one — which does not fail anywhere, it passes and counts as coverage.
            if level == .dataless {
                #expect(!room.ledger.hasEnumerated(room.localURL(of: site.parentLocalPath)), """
                Creating "\(name)" entered "\(site.parentLocalPath)", so this cell measured a materialized container while claiming a dataless one. Every other dataless cell in this suite rests on the same assumption and is equally suspect.
                """)
            }

            try await Waiter.poll("the server receives \"\(name)\"", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try await room.remoteChildren(of: site.parentRemotePath).contains { $0.name == name }
            }

            MetricsRecorder.record("client to server creation", duration: ContinuousClock.now - started, in: room, test: cell.description)

            let entry = try await room.waitForRemoteEntry(named: name, in: site.parentRemotePath)

            #expect(entry.isDirectory == (cell.item.kind != .file), """
            "\(name)" arrived on the server as \(entry.isDirectory ? "a directory" : "a file") where a \(cell.item.kind.rawValue) was created.
            """)

            switch cell.item.kind {
                case .file:
                    let arrived = try await room.remoteFingerprint(of: site.remotePath(of: name))

                    #expect(arrived == ContentFactory.fingerprint(of: content), """
                    "\(name)" reached the server with different bytes from the ones written into the domain.
                    """)

                case .folderWithChildren:
                    // Awaited rather than read once. The folder and the file inside it are two uploads, and the wait above only proves the first of them happened — so reading the listing straight afterwards catches a folder which is empty because its child is still on its way. The first run of this suite did exactly that and recorded it as the client losing a file.
                    do {
                        try await Waiter.poll("the file inside \"\(name)\" reaches the server", timeout: LiveEnvironment.scaled(.seconds(180))) {
                            try await room.remoteChildren(of: site.remotePath(of: name)).contains { $0.name == ScenarioWorld.childFixtureName }
                        }
                    } catch is WaitTimeoutError {
                        let children = try await room.remoteChildren(of: site.remotePath(of: name))

                        Issue.record("""
                        The folder reached the server without the file inside it, so a person who creates a folder with something in it gets an empty folder. It holds: \(children.map(\.name).sorted().joined(separator: ", ")).
                        """)

                        return
                    }

                    let arrived = try await room.remoteFingerprint(of: "\(site.remotePath(of: name))/\(ScenarioWorld.childFixtureName)")

                    #expect(arrived == ContentFactory.fingerprint(of: childContent), """
                    The file inside "\(name)" reached the server with different bytes from the ones written into the domain.
                    """)

                case .folderEmpty, .bundle:
                    break
            }

            ScenarioOracle.decline("noDuplicatesOrOrphans", because: ScenarioOracle.posixListingReason)
            ScenarioOracle.decline("contentPolicyInheritance", because: ScenarioOracle.unpinnedReason)
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.createdItemReason)
        }
    }
}
