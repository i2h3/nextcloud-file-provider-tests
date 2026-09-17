// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Rainmaker
import ScenarioMatrix
import ServerHarness
import Testing

///
/// Puts a client and a server into the state a ``Scenario`` describes.
///
/// This is the half the axis model deliberately does not have. The model says a cell requires an item of some kind, in some container, at some level of realization; this says what to do to a real Nextcloud server and a real File Provider domain to make that true, and then checks that it became true.
///
/// The checking is not ceremony. A precondition which is assumed rather than verified produces a cell that passes for the wrong reason, and a cell that passes for the wrong reason is worse than one that fails: it reports as coverage. Every step here distinguishes *established and verified* from *no error was raised*.
///
/// Two constraints shape the whole type, and both were measured rather than assumed.
///
/// The first is that an item can only be brought to ``RealizationLevel/dataless`` by creating it on the **server**. Anything written through the domain is materialized from birth, and the only route back is eviction — which is a different cell in the same quadrant. A test which evicts to reach dataless has quietly swapped its own scenario for another one.
///
/// The second is that reading a File Provider domain blocks in the kernel, so every wait here runs its condition on a thread of its own through ``Waiter/waitUntilBlocking(_:timeout:attemptTimeout:condition:)``. The cooperative pool is not a safe place to put a call that may never return.
///
enum ScenarioWorld {
    ///
    /// How large a `size:small` file is.
    ///
    /// Deliberately not zero. An empty file keeps its dataless flag after being read, because there was never anything to fetch to clear it — so the flag would prove nothing about a state this type exists to establish. Zero is its own size class in the model and belongs to its own cells.
    ///
    static let smallFileSize = 64 * 1024

    ///
    /// The name of the one child a `folderWithChildren` is given.
    ///
    /// Shared because a create in the server-to-client direction has to assert that this child arrived, and a suite spelling the name a second time would keep passing after this one changed it.
    ///
    static let childFixtureName = "child.bin"

    ///
    /// Build the world a scenario describes, and confirm it was built.
    ///
    /// - Parameters:
    ///     - scenario: The cell to establish the precondition of.
    ///     - room: The room to build it in.
    ///     - name: The name to give the item.
    ///
    /// - Returns: What was built.
    ///
    /// - Throws: ``ScenarioWorldError`` if the scenario asks for something this harness cannot establish, or whatever the file system, the server or the waiting raises.
    ///
    static func build(_ scenario: Scenario, in room: CleanRoom, named name: String) async throws -> ScenarioSubject {
        for placement in scenario.site.placements where placement.container.type != .standard {
            throw ScenarioWorldError.unsupported("the \(placement.container.type.rawValue) container, which needs sharing or group-folder provisioning this harness does not have")
        }

        let source = scenario.site.placements[0]

        if let trash = scenario.trash {
            try await confirmTrash(trash, on: room)
        }

        // A move's cell pins the state of its containers, so the source container is entered only if the cell says it should be. Entering it regardless is how the first version of this quietly measured the materialized case for every cell claiming a dataless one.
        let sourceLevel = scenario.realization.isAboutParents ? scenario.realization.levels.first : .materialized

        let (parentRemotePath, parentLocalPath) = try await ScenarioWorldError.doing("creating the container the item goes in") {
            try await makeParent(source.location, entering: sourceLevel != .dataless, in: room)
        }

        // A move needs its destination to exist before the item is created, because a cell may ask for that destination to be left unentered afterwards and building it later would be the enumeration it is meant to avoid.
        var destination: (remote: String, local: String)?

        if case let .transfer(_, to) = scenario.site {
            let destinationLevel = scenario.realization.levels.count > 1 ? scenario.realization.levels[1] : .materialized

            destination = try await ScenarioWorldError.doing("creating the container the item moves into") {
                try await makeParent(to.location, entering: destinationLevel != .dataless, in: room)
            }
        }

        try await ScenarioWorldError.doing("creating the \(scenario.item.kind.rawValue) \"\(name)\" on the server under \"\(parentRemotePath)\"") {
            try await createItem(scenario, named: name, at: parentRemotePath, in: room)
        }

        // The last free moment: after the operation the item's previous identity cannot be recovered, and an oracle comparing identities would have nothing to compare against.
        let before = try await ScenarioWorldError.doing("reading back what the server stored for \"\(name)\"") {
            try await room.waitForRemoteEntry(named: name, in: parentRemotePath)
        }

        let localPath = parentLocalPath.isEmpty ? name : "\(parentLocalPath)/\(name)"
        let url = room.localURL(of: localPath)

        // How the item is awaited depends on what the cell says about its container, and getting this wrong would not fail — it would quietly establish the opposite precondition and pass.
        let mustNotEnterParent = scenario.realization.levels.first == .dataless && scenario.realization.isAboutParents

        try await ScenarioWorldError.doing("waiting for \"\(localPath)\" to reach the client") {
            guard mustNotEnterParent else {
                // Polling the parent, one level, never the item. A listing is `readdir` plus one `lstat` per entry, so it neither opens nor reads anything.
                try await Waiter.waitUntilBlocking("\"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                    try room.localChildren(of: parentLocalPath).contains { $0.name == name }
                }

                return
            }

            // The container must still be unentered when the operation happens, so the item is awaited by looking it up directly rather than by listing what it is in.
            //
            // This rests on an assumption nobody has measured: that a name lookup inside a container which was never enumerated does not drive that container's enumerator. If it is wrong, the lookup either never succeeds — and this wait times out, saying so — or it succeeds by enumerating, in which case the cell silently measures the materialized case instead. The first is loud and the second is why the ledger is asserted immediately afterwards.
            try await Waiter.waitUntilBlocking("\"\(localPath)\" can be looked up without entering its container", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try LocalNode.at(url) != nil
            }

            guard !room.ledger.hasEnumerated(room.localURL(of: parentLocalPath)) else {
                throw ScenarioWorldError.unsupported("""
                a container which stays unentered while the item inside it is awaited: the wait entered "\(parentLocalPath)" after all, so the cell would have measured a materialized container while claiming a dataless one
                """)
            }
        }

        let wasEnumerated: Bool

        switch scenario.realization {
            case let .item(level):
                wasEnumerated = try await ScenarioWorldError.doing("bringing \"\(localPath)\" to \(level.rawValue)") {
                    try await realize(level, kind: scenario.item.kind, at: url, path: localPath, in: room)
                }

            case let .parents(sourceLevel, destinationLevel):
                // A move pins the state of the two containers and says nothing about the item, which arrives as a placeholder and is left as one.
                try await ScenarioWorldError.doing("bringing the source container \"\(parentLocalPath.isEmpty ? "/" : parentLocalPath)\" to \(sourceLevel.rawValue)") {
                    try await realizeContainer(sourceLevel, path: parentLocalPath, in: room)
                }

                try await ScenarioWorldError.doing("bringing the destination container \"\((destination?.local).map { $0.isEmpty ? "/" : $0 } ?? "/")\" to \(destinationLevel.rawValue)") {
                    try await realizeContainer(destinationLevel, path: destination?.local ?? "", in: room)
                }

                wasEnumerated = false

            case .parent:
                throw ScenarioWorldError.unsupported("a realization describing the parent of an item which does not exist yet, which only a create has")
        }

        let remotePath = parentRemotePath == "/" ? "/\(name)" : "\(parentRemotePath)/\(name)"
        var fingerprint: String?

        if case let .item(level) = scenario.realization {
            fingerprint = try await ScenarioWorldError.doing("confirming \"\(localPath)\" really is \(level.rawValue)") {
                try await verify(level, scenario: scenario, at: url, remotePath: remotePath, in: room, wasEnumerated: wasEnumerated)
            }
        } else if scenario.item.kind == .file {
            fingerprint = try await ScenarioWorldError.doing("reading back the content of \"\(remotePath)\"") {
                try await room.remoteFingerprint(of: remotePath)
            }
        }

        return ScenarioSubject(
            name: name,
            parentRemotePath: parentRemotePath,
            parentLocalPath: parentLocalPath,
            before: before,
            fingerprint: fingerprint,
            destinationRemotePath: destination?.remote,
            destinationLocalPath: destination?.local,
            wasEnumerated: wasEnumerated
        )
    }

    ///
    /// Build the world a `create` cell describes: the container, and deliberately nothing in it.
    ///
    /// The other quadrants establish an item and hand it over. This one must not: the item is what the test is about to make, and a world which created it first would be testing something else entirely. What a create pins instead is the container — ``ScenarioMatrix/Realization/parent(_:)`` rather than ``ScenarioMatrix/Realization/item(_:)`` — and that is the whole precondition.
    ///
    /// The dataless container is the case worth the trouble. A cell asking for one is asking whether the client can accept a new item in a folder it has never listed, which is the ordinary situation of a user saving a file into a synced folder they have not opened in this session. Establishing it means not entering the container, which in turn means the suite may not find its way to the item by listing what it is in.
    ///
    /// - Parameters:
    ///     - scenario: The cell to establish the precondition of.
    ///     - room: The room to build it in.
    ///
    /// - Returns: The container which was established.
    ///
    /// - Throws: ``ScenarioWorldError`` if the scenario asks for something this harness cannot establish, or whatever the file system, the server or the waiting raises.
    ///
    static func prepareCreation(_ scenario: Scenario, in room: CleanRoom) async throws -> ScenarioCreationSite {
        guard case let .parent(level) = scenario.realization else {
            throw ScenarioWorldError.unsupported("a realization which does not describe the container an item is created into, which is the only shape a create has")
        }

        for placement in scenario.site.placements where placement.container.type != .standard {
            throw ScenarioWorldError.unsupported("the \(placement.container.type.rawValue) container, which needs sharing or group-folder provisioning this harness does not have")
        }

        if let trash = scenario.trash {
            try await confirmTrash(trash, on: room)
        }

        let (remote, local) = try await ScenarioWorldError.doing("creating the container the item is created in") {
            try await makeParent(scenario.site.target.location, entering: level != .dataless, in: room)
        }

        try await ScenarioWorldError.doing("bringing the container \"\(local.isEmpty ? "/" : local)\" to \(level.rawValue)") {
            try await realizeContainer(level, path: local, in: room)
        }

        // Confirmed rather than assumed, for the same reason every other precondition here is. A cell which claims a dataless container and got a materialized one does not fail — it passes, having measured the wrong thing, and reports as coverage.
        if level == .dataless, room.ledger.hasEnumerated(room.localURL(of: local)) {
            throw ScenarioWorldError.unsupported("""
            a container which stays unentered: "\(local)" was listed while it was being established, so the cell would have measured a materialized container while claiming a dataless one
            """)
        }

        return ScenarioCreationSite(parentRemotePath: remote, parentLocalPath: local, wasEntered: level != .dataless)
    }

    ///
    /// Confirm the server really does what the cell assumes about its trash bin.
    ///
    /// A cell which says `trash:with` is not describing a wish. It is describing a server, and whether that server keeps deleted items is a setting an administrator can turn off — `files_trashbin` is an application like any other on a Nextcloud server, and the client's own extension branches on `capabilities.files.undelete` rather than assuming it.
    ///
    /// Without this check, running the deletion cells against a server with the trash disabled produces twelve failures reading *the item was deleted and never reached the trash*, which is a finished and entirely wrong bug report about the client. The setting is the server's, the behaviour is correct, and the suite would be the only thing at fault.
    ///
    /// So the axis value is read back rather than trusted, which is the same rule that applies to anything this harness sets up: a precondition nobody verified is a cell that passes, or fails, for the wrong reason.
    ///
    /// - Parameters:
    ///     - trash: What the cell assumes.
    ///     - room: The room, whose server is asked.
    ///
    /// - Throws: ``ScenarioWorldError`` if the server does not match, or whatever asking it raises.
    ///
    private static func confirmTrash(_ trash: TrashSupport, on room: CleanRoom) async throws {
        let wanted = trash == .with

        // Established rather than only checked. `files_trashbin` is an application an administrator may disable, and until this could be turned off, sixty cells of the matrix described a server nothing here could produce. Toggled per room because the suites are serialized and a room holds its server to itself.
        if try await isTrashEnabled(on: room) != wanted {
            try await ScenarioWorldError.doing("turning the server's trash bin \(wanted ? "on" : "off")") {
                try await TrashApplication.setEnabled(wanted, inContainer: room.underTest.containerIdentifier)
            }
        }

        // Read back after the change, and read back from the same place the client reads it. Setting an application's state and assuming the capability followed is the shape of precondition this type exists to refuse: the cells which depend on it would pass while describing a server that was never produced.
        let isEnabled = try await ScenarioWorldError.doing("asking the server whether it keeps deleted items") {
            try await Waiter.poll("the server reports its trash bin as \(wanted ? "available" : "unavailable")", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try await isTrashEnabled(on: room) == wanted
            }

            return wanted
        }

        guard isEnabled == wanted else {
            throw ScenarioWorldError.unsupported("""
            a server whose trash bin is \(wanted ? "enabled" : "disabled"), because this one reports `capabilities.files.undelete` as \(isEnabled). The cell describes a server this run is not talking to, so nothing it would have measured is about the client
            """)
        }
    }

    ///
    /// Ask the server whether it keeps deleted items, in the words the client reads.
    ///
    /// - Parameters:
    ///     - room: The room whose server is asked.
    ///
    /// - Returns: Whether deleted items are recoverable.
    ///
    /// - Throws: Whatever asking raises.
    ///
    private static func isTrashEnabled(on room: CleanRoom) async throws -> Bool {
        let capabilities = try await room.server.capabilities()

        // Absent rather than false is still an answer of no: a server which does not advertise the capability is one whose client is expected to treat trash as unavailable.
        return try capabilities.get(Trashing.self)?.undelete ?? false
    }

    ///
    /// Establish the container the item will live in.
    ///
    /// The domain root needs nothing: it is enumerated once while the room is built, before any test body runs, which is the harness fact behind the model's rule that a root container is always materialized.
    ///
    /// - Parameters:
    ///     - location: Where the item goes.
    ///     - entering: Whether the container may be listed once to reveal what is in it. False for a cell which pins it as dataless.
    ///     - room: The room.
    ///
    /// - Returns: The container as the server spells it, and as the domain spells it.
    ///
    /// - Throws: Whatever creating or waiting raises.
    ///
    private static func makeParent(_ location: Location, entering: Bool, in room: CleanRoom) async throws -> (remote: String, local: String) {
        guard location == .subdirectory else {
            return ("/", "")
        }

        let name = "box"

        // Created only if it is not already there, so that a room may build more than one world. A suite which repeats a cell to measure how often something happens builds dozens in the same room, and the first version of this threw on the second — which the characterisation suite counted as nineteen trials in twenty dropped before measuring, and reported as such rather than as a rate.
        let existing = try await room.remoteChildren().contains { $0.name == name && $0.isDirectory }

        if !existing {
            // One `MKCOL`, so a deeper path would need a call per level. One level is the whole axis: the model distinguishes only root from not-root.
            try await room.server.createDirectory("/\(name)")
            _ = try await room.waitForRemoteEntry(named: name)
        }

        try await Waiter.waitUntilBlocking("\"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
            try room.localChildren().contains { $0.name == name && $0.kind == .directory }
        }

        // Entered deliberately and exactly once, where the cell permits it. For a cell which pins this container as dataless it must not be entered at all, and the item inside it is found by looking its path up instead.
        if entering {
            _ = try room.localChildren(of: name)
        }

        return ("/\(name)", name)
    }

    ///
    /// Create the item on the server.
    ///
    /// Always on the server, never through the domain. See the note on this type about why that is forced rather than stylistic.
    ///
    /// - Parameters:
    ///     - scenario: The cell.
    ///     - name: The name to give it.
    ///     - parent: The container, as the server spells it.
    ///     - room: The room.
    ///
    /// - Throws: ``ScenarioWorldError`` for a kind this harness cannot build, or whatever uploading raises.
    ///
    static func createItem(_ scenario: Scenario, named name: String, at parent: String, in room: CleanRoom) async throws {
        let path = parent == "/" ? "/\(name)" : "\(parent)/\(name)"

        switch scenario.item.kind {
            case .file:
                guard scenario.item.size == .small else {
                    throw ScenarioWorldError.unsupported("a file of size \(scenario.item.size?.rawValue ?? "unspecified"), which is its own cell")
                }

                try await ServerWorkspace.withFixture(named: name, size: smallFileSize, seed: 71) { source, _ in
                    try await room.server.upload(source, to: parent, force: true)
                }

            case .folderEmpty:
                try await room.server.createDirectory(path)

            case .folderWithChildren:
                try await room.server.createDirectory(path)

                try await ServerWorkspace.withFixture(named: childFixtureName, size: smallFileSize, seed: 72) { source, _ in
                    try await room.server.upload(source, to: path, force: true)
                }

            case .bundle:
                throw ScenarioWorldError.unsupported("a package, which needs a fixture builder this harness does not have")
        }
    }

    ///
    /// Bring the item to the level of realization the cell asks for.
    ///
    /// - Parameters:
    ///     - level: The level.
    ///     - kind: What sort of item it is.
    ///     - url: Where it is.
    ///     - path: Its path relative to the domain.
    ///     - room: The room.
    ///
    /// - Returns: Whether this test enumerated the item, which is what realization means for a directory.
    ///
    /// - Throws: ``ScenarioWorldError`` for a level this harness cannot establish, or whatever materializing raises.
    ///
    private static func realize(_ level: RealizationLevel, kind: ItemKind, at url: URL, path: String, in room: CleanRoom) async throws -> Bool {
        switch level {
            case .dataless:
                // Nothing to do, and that is the point: the item arrived as a placeholder and nothing here is permitted to touch it.
                return false

            case .materialized:
                guard kind != .file else {
                    _ = try Materialization.materialize(url)

                    return false
                }

                // A directory is materialized by being entered. Shallow by definition: its children stay as they were, which is what separates this from `materializedDeep`.
                _ = try room.localChildren(of: path)

                return true

            case .unknown, .evicted, .materializedDeep:
                throw ScenarioWorldError.unsupported("the realization level \(level.rawValue), which this harness cannot yet establish and verify")
        }
    }

    ///
    /// Bring a container to the level of realization a move's cell asks of it.
    ///
    /// Containers are realized by being entered, so `materialized` is one listing and `dataless` is the deliberate absence of one. There is nothing else to do, which is exactly why this is the half of the world that is easiest to destroy by accident: any wait which polls a listing of the container establishes the state it was supposed to preserve.
    ///
    /// The domain root is a special case and not one this has to handle. It is enumerated once while the room is built, before any test body runs, so a cell asking for a materialized root is already satisfied and a cell asking for a dataless root is one the model does not generate.
    ///
    /// - Parameters:
    ///     - level: What the cell asks for.
    ///     - path: The container, relative to the domain. Empty is the root.
    ///     - room: The room.
    ///
    /// - Throws: ``ScenarioWorldError`` for a level a container cannot be brought to, or whatever listing raises.
    ///
    private static func realizeContainer(_ level: RealizationLevel, path: String, in room: CleanRoom) async throws {
        switch level {
            case .materialized:
                _ = try room.localChildren(of: path)

            case .dataless:
                guard !path.isEmpty else {
                    throw ScenarioWorldError.unsupported("a dataless domain root, which is enumerated while the room is built and cannot be returned to")
                }

            // Nothing to do, and nothing may be done: this container must not be listed by anything between here and the operation.

            case .unknown, .evicted, .materializedDeep:
                throw ScenarioWorldError.unsupported("a container at \(level.rawValue), which this harness cannot establish and confirm")
        }
    }

    ///
    /// Confirm the precondition actually holds.
    ///
    /// - Parameters:
    ///     - level: The level asked for.
    ///     - scenario: The cell.
    ///     - url: Where the item is.
    ///     - remotePath: Where it is on the server, from the files root.
    ///     - room: The room.
    ///     - wasEnumerated: Whether this test entered it.
    ///
    /// - Returns: The fingerprint of the content, where the item has content and it was fetched.
    ///
    /// - Throws: Whatever inspection raises. An unverifiable precondition fails here rather than in an oracle, so that the report says the measurement did not happen rather than that the client is wrong.
    ///
    private static func verify(_ level: RealizationLevel, scenario: Scenario, at url: URL, remotePath: String, in room: CleanRoom, wasEnumerated: Bool) async throws -> String? {
        let node = try #require(try LocalNode.at(url), "The item did not reach the client, so the cell's precondition was never established.")

        #expect(node.kind == (scenario.item.kind == .file ? .file : .directory), "The item reached the client as the wrong sort of thing.")

        guard scenario.item.kind == .file else {
            // For a directory the only honest statement is what this test did to it, and the ledger is the record of that.
            #expect(room.ledger.hasEnumerated(url) == wasEnumerated, "The record of whether this directory was entered does not match what the precondition asked for.")

            return nil
        }

        guard level == .materialized else {
            // Awaited together rather than read once: these do not settle at the same instant, and reading one of them early is how a placeholder reports a size it does not yet have.
            try await Waiter.waitUntilBlocking("\(scenario.item.kind.rawValue) \"\(url.lastPathComponent)\" settles as a placeholder", timeout: LiveEnvironment.scaled(.seconds(60))) {
                guard let node = try LocalNode.at(url) else {
                    return false
                }

                return node.isDataless && node.size == Int64(smallFileSize) && node.allocatedBlocks == 0
            }

            return nil
        }

        #expect(!node.isDataless, "The file was asked to be materialized and is still a placeholder.")

        // The full path, not the last component. A bare name resolves at the domain root and nowhere else, so reading it this way worked for every cell at `at:standard:root` and failed for every cell in a subdirectory — which is the shape of mistake a matrix finds and a hand-written test, always at the root, never can.
        return try await room.remoteFingerprint(of: remotePath)
    }
}
