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
        guard case let .single(placement) = scenario.site else {
            throw ScenarioWorldError.unsupported("a scenario spanning two placements, which only a move has")
        }

        guard placement.container.type == .standard else {
            throw ScenarioWorldError.unsupported("the \(placement.container.type.rawValue) container, which needs sharing or group-folder provisioning this harness does not have")
        }

        guard case let .item(level) = scenario.realization else {
            throw ScenarioWorldError.unsupported("a realization which describes something other than the item itself")
        }

        if let trash = scenario.trash {
            try await confirmTrash(trash, on: room)
        }

        let (parentRemotePath, parentLocalPath) = try await ScenarioWorldError.doing("creating the container the item goes in") {
            try await makeParent(placement.location, in: room)
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

        try await ScenarioWorldError.doing("waiting for \"\(localPath)\" to reach the client") {
            // Polling the parent, one level, never the item. A listing is `readdir` plus one `lstat` per entry, so it neither opens nor reads anything.
            try await Waiter.waitUntilBlocking("\"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren(of: parentLocalPath).contains { $0.name == name }
            }
        }

        let wasEnumerated = try await ScenarioWorldError.doing("bringing \"\(localPath)\" to \(level.rawValue)") {
            try await realize(level, kind: scenario.item.kind, at: url, path: localPath, in: room)
        }

        let remotePath = parentRemotePath == "/" ? "/\(name)" : "\(parentRemotePath)/\(name)"

        let fingerprint = try await ScenarioWorldError.doing("confirming \"\(localPath)\" really is \(level.rawValue)") {
            try await verify(level, scenario: scenario, at: url, remotePath: remotePath, in: room, wasEnumerated: wasEnumerated)
        }

        return ScenarioSubject(
            name: name,
            parentRemotePath: parentRemotePath,
            parentLocalPath: parentLocalPath,
            before: before,
            fingerprint: fingerprint,
            wasEnumerated: wasEnumerated
        )
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
        let isEnabled = try await ScenarioWorldError.doing("asking the server whether it keeps deleted items") {
            let capabilities = try await room.server.capabilities()

            // Absent rather than false is still an answer of no: a server which does not advertise the capability is one whose client is expected to treat trash as unavailable.
            return try capabilities.get(Trashing.self)?.undelete ?? false
        }

        guard isEnabled == (trash == .with) else {
            throw ScenarioWorldError.unsupported("""
            a server whose trash bin is \(trash == .with ? "enabled" : "disabled"), because this one reports `capabilities.files.undelete` as \(isEnabled). The cell describes a server this run is not talking to, so nothing it would have measured is about the client
            """)
        }
    }

    ///
    /// Establish the container the item will live in.
    ///
    /// The domain root needs nothing: it is enumerated once while the room is built, before any test body runs, which is the harness fact behind the model's rule that a root container is always materialized.
    ///
    /// - Parameters:
    ///     - location: Where the item goes.
    ///     - room: The room.
    ///
    /// - Returns: The container as the server spells it, and as the domain spells it.
    ///
    /// - Throws: Whatever creating or waiting raises.
    ///
    private static func makeParent(_ location: Location, in room: CleanRoom) async throws -> (remote: String, local: String) {
        guard location == .subdirectory else {
            return ("/", "")
        }

        let name = "box"

        // One `MKCOL`, so a deeper path would need a call per level. One level is the whole axis: the model distinguishes only root from not-root.
        try await room.server.createDirectory("/\(name)")
        _ = try await room.waitForRemoteEntry(named: name)

        try await Waiter.waitUntilBlocking("\"\(name)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
            try room.localChildren().contains { $0.name == name && $0.kind == .directory }
        }

        // Entered deliberately and exactly once. The model pins only the item's realization for this quadrant, so the container's own state is unconstrained — and the item must be revealed by something, which is this.
        _ = try room.localChildren(of: name)

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
    private static func createItem(_ scenario: Scenario, named name: String, at parent: String, in room: CleanRoom) async throws {
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

                try await ServerWorkspace.withFixture(named: "child.bin", size: smallFileSize, seed: 72) { source, _ in
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
