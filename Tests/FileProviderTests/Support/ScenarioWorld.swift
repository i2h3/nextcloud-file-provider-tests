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
    /// How large a `size:large` file is.
    ///
    /// Comfortably above the client's chunking threshold, which is what the axis is for: a chunked upload takes a different path through the client and is assembled on the server afterwards, and assembly is its own way of ending up with content which does not match.
    ///
    static let largeFileSize = 12 * 1024 * 1024

    ///
    /// The name of the one child a `folderWithChildren` is given.
    ///
    /// Shared because a create in the server-to-client direction has to assert that this child arrived, and a suite spelling the name a second time would keep passing after this one changed it.
    ///
    static let childFixtureName = "child.bin"

    ///
    /// The extension which makes a directory a package.
    ///
    /// A bundle is not a kind of file the system stores — it is a directory the Finder and the framework agree to present as one item, and what makes them agree is the extension. `.rtfd` is chosen because it is a document type macOS has recognised as a package since long before File Provider existed, so a client which mishandles it is mishandling something ordinary rather than something exotic.
    ///
    static let bundleExtension = "rtfd"

    ///
    /// The file a bundle is given so that it has something inside it.
    ///
    static let bundleContentName = "TXT.rtf"

    ///
    /// Where an item's bytes live, relative to the item itself.
    ///
    /// A file is its own content; a bundle's content is a file inside it. The model puts them in the same class — ``ScenarioMatrix/ItemKind/hasOwnContent`` is true for both, so a content update is legal on a package — and this is the one place that difference has to be spelled out.
    ///
    /// - Parameters:
    ///     - kind: What the cell asks for.
    ///
    /// - Returns: The path component to append, or `nil` when the item is its own content.
    ///
    static func contentComponent(of kind: ItemKind) -> String? {
        kind == .bundle ? bundleContentName : nil
    }

    ///
    /// Name an item so that the system will treat it as the kind the cell asks for.
    ///
    /// The kind is not a property the harness can declare — it follows from the name for a bundle and from being a directory for the rest. Until this existed every suite spelled the rule out itself, in the one shape that had no bundle in it.
    ///
    /// - Parameters:
    ///     - base: The stem, which says what the test is doing.
    ///     - kind: What the cell asks for.
    ///
    /// - Returns: The name to use.
    ///
    static func name(_ base: String, for kind: ItemKind, encoding: FilenameEncoding? = nil) -> String {
        let stem = stem(base, encoding: encoding)

        switch kind {
            case .file: return "\(stem).bin"
            case .bundle: return "\(stem).\(bundleExtension)"
            case .folderEmpty, .folderWithChildren: return stem
        }
    }

    ///
    /// The stem of a name, in the form the cell's encoding axis asks for.
    ///
    /// An ASCII name cannot carry this axis: precomposed and decomposed forms of `doomed` are the same bytes, so a cell claiming to test normalisation would test nothing. Every encoded cell therefore uses a stem with a character that has both forms, and the two are genuinely different on the wire — which is the whole point, because macOS stores one form and the server stores whatever it was sent.
    ///
    /// - Parameters:
    ///     - base: What the test would have called it.
    ///     - encoding: What the cell asks for.
    ///
    /// - Returns: The stem.
    ///
    static func stem(_ base: String, encoding: FilenameEncoding?) -> String {
        switch encoding {
            case .none: return base
            case .nfc: return "\(base)-café".precomposedStringWithCanonicalMapping
            case .nfd: return "\(base)-café".decomposedStringWithCanonicalMapping
            case .caseCollision: return "\(base)-Sibling"
        }
    }

    ///
    /// The name of the sibling a `caseCollision` cell needs to collide with.
    ///
    /// The axis describes an item whose name differs from an existing one only by case, so the existing one has to exist first. On a case-insensitive volume the two cannot both be written, and the system renames the arriving item — the bounce whose evidence is ``ExtendedAttribute/beforeBounce``.
    ///
    /// - Parameters:
    ///     - base: What the test would have called it.
    ///     - kind: What sort of thing it is.
    ///
    /// - Returns: The sibling's name.
    ///
    static func sibling(_ base: String, for kind: ItemKind) -> String {
        name("\(base)-sibling", for: kind)
    }

    ///
    /// Whether a name the client shows is the one a cell asked for.
    ///
    /// Compared in one normalisation form, because the two sides store different ones and a byte comparison would report a difference which is not one. A bounced name matches too, and says so through the attribute recording what it was bounced from.
    ///
    /// - Parameters:
    ///     - candidate: What the client shows.
    ///     - requested: What was asked for.
    ///     - url: Where the candidate is, for reading the bounce attribute.
    ///
    /// - Returns: Whether they are the same item.
    ///
    static func matches(_ candidate: String, requested: String, at url: URL? = nil) -> Bool {
        guard candidate.precomposedStringWithCanonicalMapping != requested.precomposedStringWithCanonicalMapping else {
            return true
        }

        guard let url, let bounced = ExtendedAttribute.string(of: ExtendedAttribute.beforeBounce, at: url) else {
            return false
        }

        return bounced.precomposedStringWithCanonicalMapping == requested.precomposedStringWithCanonicalMapping
    }

    ///
    /// How many bytes a cell's file holds.
    ///
    /// The model treats the size of a file as an axis, and until this existed the harness treated it as a constant: everything was ``smallFileSize`` and the cells asking for anything else were excluded. An empty file is not a degenerate small one — "nothing to upload" is a case a client can quietly skip rather than perform, which is why the model gives it a cell of its own.
    ///
    /// - Parameters:
    ///     - size: What the cell asks for.
    ///
    /// - Returns: The number of bytes, or `nil` for a size this harness cannot produce.
    ///
    static func bytes(for size: FileSize?) -> Int? {
        switch size {
            case .empty: 0
            case .small, nil: smallFileSize
            case .large: largeFileSize
            case .some: nil
        }
    }

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

        if scenario.encoding == .caseCollision {
            // The axis describes an item whose name differs from an existing one only by case, so the existing one has to exist first. It is created on the server, where both names can be held at once; what the client does when it cannot hold both is the thing under test.
            try await ScenarioWorldError.doing("creating the sibling \"\(name)\" is meant to collide with") {
                try await ServerWorkspace.withFixture(named: siblingName(of: name), size: smallFileSize, seed: 74) { source, _ in
                    try await room.server.upload(source, to: parentRemotePath, force: true)
                }

                _ = try await room.waitForRemoteEntry(named: siblingName(of: name), in: parentRemotePath)
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
                try await Waiter.waitUntilBlocking(
                    "\"\(name)\" reaches the client",
                    timeout: LiveEnvironment.scaled(.seconds(180)),
                    // The condition has to swallow its error to keep polling, because "not yet" and "never" are the same absence to a directory listing. This is where what it swallowed is finally said, and it is not a nicety: three timeouts reading "before-Sibling.bin never reached the client" were a container holding that name's lowercase sibling and nothing else, which is a sentence about the client rather than about the wait.
                    diagnosis: { describe(parentLocalPath, in: room) }
                ) {
                    // Asked for by whatever the client decided to call it, because a cell which arranged a name collision does not get the name it asked for and waiting for that one would wait forever.
                    (try? resolveLocalName(of: name, for: scenario, under: parentLocalPath, in: room)) != nil
                }

                return
            }

            // The container must still be unentered when the operation happens, so the item is awaited by looking it up directly rather than by listing what it is in.
            //
            // This rests on an assumption nobody has measured: that a name lookup inside a container which was never enumerated does not drive that container's enumerator. If it is wrong, the lookup either never succeeds — and this wait times out, saying so — or it succeeds by enumerating, in which case the cell silently measures the materialized case instead. The first is loud and the second is why the ledger is asserted immediately afterwards.
            try await Waiter.waitUntilBlocking(
                "\"\(localPath)\" can be looked up without entering its container",
                timeout: LiveEnvironment.scaled(.seconds(180)),
                // Deliberately not a listing. Everywhere else the diagnosis lists the container to say what was there instead, and here that listing is the exact thing the cell forbids — a timeout is not a reason to perform the enumeration the cell was built to avoid, because the next thing anyone reads is the diagnosis and it would be describing a container this line had just changed.
                diagnosis: { "nothing at that path, and its container was left unlisted because entering it is what this cell forbids" }
            ) {
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
                try await verify(level, scenario: scenario, at: url, path: localPath, remotePath: remotePath, in: room, wasEnumerated: wasEnumerated)
            }
        } else if scenario.item.kind == .file {
            fingerprint = try await ScenarioWorldError.doing("reading back the content of \"\(remotePath)\"") {
                try await room.remoteFingerprint(of: remotePath)
            }
        }

        let localName = try await ScenarioWorldError.doing("finding the name the client gave \"\(name)\"") {
            try resolveLocalName(of: name, for: scenario, under: parentLocalPath, in: room)
        }

        return ScenarioSubject(
            name: name,
            localName: localName,
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
    /// What a container holds, in a form a timeout can be read with.
    ///
    /// Only ever called when a wait has already run out, so the listing it performs costs nothing the cell still needed — and the cell it describes is over either way.
    ///
    /// - Parameters:
    ///     - path: The container, relative to the domain.
    ///     - room: The room.
    ///
    /// - Returns: The sentence.
    ///
    static func describe(_ path: String, in room: CleanRoom) -> String {
        let place = path.isEmpty ? "the domain's root" : "\"\(path)\""

        do {
            let names = try room.localChildren(of: path).map(\.name).sorted()

            guard !names.isEmpty else {
                return "\(place) empty"
            }

            return "\(place) holding \(names.joined(separator: ", "))"
        } catch {
            return "\(place) could not be listed: \(error)"
        }
    }

    ///
    /// The name of the sibling a colliding cell needs to collide with.
    ///
    /// The same name in a different case, which is what "differs only by case" means, and what a case-insensitive volume cannot hold twice.
    ///
    /// - Parameters:
    ///     - name: The item's name.
    ///
    /// - Returns: The sibling's name.
    ///
    static func siblingName(of name: String) -> String {
        name.lowercased()
    }

    ///
    /// Find the name the client actually gave an item.
    ///
    /// The same as the name it was given, except where the cell arranged a collision: there the system renames the arriving item and records what it renamed it from. Both routes are tried, because the attribute is evidence about a bounce which has happened and says nothing when one has not.
    ///
    /// - Parameters:
    ///     - name: The name the item was given.
    ///     - scenario: The cell, whose encoding says whether a bounce was arranged.
    ///     - parentLocalPath: The container, relative to the domain.
    ///     - room: The room.
    ///
    /// - Returns: The name on disk.
    ///
    /// - Throws: ``ScenarioWorldError`` if the cell arranged a collision and no item can be found which answers to it.
    ///
    static func resolveLocalName(of name: String, for scenario: Scenario, under parentLocalPath: String, in room: CleanRoom) throws -> String {
        // Listing is safe here and only here: this is the path taken when the cell permits its container to be entered, and the other path — for a container which must stay unentered — looks the item up instead and never arrives here.
        let listing = try room.localChildren(of: parentLocalPath)

        guard scenario.encoding == .caseCollision else {
            // The item still has to be there. Returning the requested name without looking was a wait which always succeeded, so every quadrant which builds an item moved on before the item existed and then failed on its absence, one cell at a time.
            guard listing.contains(where: { $0.name == name }) else {
                throw ScenarioWorldError.unsupported("""
                an item named "\(name)": the container holds \(listing.map(\.name).sorted().joined(separator: ", "))
                """)
            }

            return name
        }

        let sibling = siblingName(of: name)

        let entries = listing

        if let bounced = entries.first(where: { entry in
            ExtendedAttribute.string(of: ExtendedAttribute.beforeBounce, at: room.localURL(of: parentLocalPath.isEmpty ? entry.name : "\(parentLocalPath)/\(entry.name)")) == name
        }) {
            // Recorded rather than asserted, and recorded precisely because both outcomes are legal. Which one a volume produces is a property of the volume, so a cell demanding either would fail on a machine formatted differently — and a cell which quietly accepted both would pass without saying what it saw, which is how an axis stops measuring anything.
            ScenarioOracle.observe("\"\(name)\" was bounced to \"\(bounced.name)\" because \"\(sibling)\" already held the name", in: room)

            return bounced.name
        }

        // No bounce: the system held both names after all, which is a legitimate outcome on a case-sensitive volume and worth not mistaking for a failure to arrive.
        guard entries.contains(where: { $0.name == name }) else {
            throw ScenarioWorldError.unsupported("""
            an item which answers to "\(name)": the container holds \(entries.map(\.name).sorted().joined(separator: ", ")), none of which is that name and none of which records having been renamed from it. Its sibling "\(sibling)" is what it was meant to collide with
            """)
        }

        ScenarioOracle.observe("\"\(name)\" and \"\(sibling)\" are both held, so this volume distinguishes them by case and no bounce was needed", in: room)

        return name
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

        try await Waiter.waitUntilBlocking(
            "\"\(name)\" reaches the client",
            timeout: LiveEnvironment.scaled(.seconds(180)),
            diagnosis: { describe("", in: room) }
        ) {
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
                guard let size = bytes(for: scenario.item.size) else {
                    throw ScenarioWorldError.unsupported("a file of size \(scenario.item.size?.rawValue ?? "unspecified"), which takes a different path through the client and has never been exercised here")
                }

                try await ServerWorkspace.withFixture(named: name, size: size, seed: 71) { source, _ in
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
                // A package is a directory with a recognised extension and something inside it. Built the same way on the server as any other directory, because that is all the server sees: whether it is one item or a tree is a question the Finder and the framework answer, and the whole point of these cells is that the two sides disagree about it.
                try await room.server.createDirectory(path)

                try await ServerWorkspace.withFixture(named: bundleContentName, size: smallFileSize, seed: 73) { source, _ in
                    try await room.server.upload(source, to: path, force: true)
                }
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

            case .evicted:
                // Fetched, then dropped. The model keeps this apart from `dataless` because the item's history differs — it has been through the provider once and takes a re-fetch path rather than a first-fetch path, which it calls a bug magnet — even though the file system shows the same three numbers for both afterwards.
                guard kind == .file else {
                    throw ScenarioWorldError.unsupported("an evicted \(kind.rawValue), because eviction applies to content and a directory has none of its own")
                }

                _ = try Materialization.materialize(url)

                guard Materialization.evict(url) else {
                    throw ScenarioWorldError.unsupported("an evicted file, because the system would not accept the eviction it was asked for")
                }

                try await Waiter.waitUntilBlocking("\"\(url.lastPathComponent)\" settles as evicted", timeout: LiveEnvironment.scaled(.seconds(60))) {
                    try LocalNode.at(url)?.allocatedBlocks == 0
                }

                return false

            case .materializedDeep:
                // One level down, child by child, because that is the only way there is: asking the system to download a directory materializes its immediate children and stops. The model emits this level only for a folder with children, where it is genuinely a different state from having entered the folder.
                guard kind == .folderWithChildren else {
                    throw ScenarioWorldError.unsupported("a deeply materialized \(kind.rawValue), which the model does not distinguish from a materialized one")
                }

                for child in try room.localChildren(of: path) {
                    _ = try Materialization.materialize(room.localURL(of: "\(path)/\(child.name)"))
                }

                return true

            case .unknown:
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

            case .materializedDeep:
                // A container is deeply materialized by being entered and then having its children fetched — the same one level down the item case takes, because that is the only depth the system offers. For a create the container is usually empty at this point, which makes this the same as materialized; the cell still differs in what it claims, and claiming it correctly costs one listing.
                for child in try room.localChildren(of: path) where child.kind == .file {
                    _ = try Materialization.materialize(room.localURL(of: path.isEmpty ? child.name : "\(path)/\(child.name)"))
                }

            case .unknown, .evicted:
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
    private static func verify(_ level: RealizationLevel, scenario: Scenario, at url: URL, path: String, remotePath: String, in room: CleanRoom, wasEnumerated: Bool) async throws -> String? {
        let node = try #require(try LocalNode.at(url), "The item did not reach the client, so the cell's precondition was never established.")

        #expect(node.kind == (scenario.item.kind == .file ? .file : .directory), "The item reached the client as the wrong sort of thing.")

        guard scenario.item.kind == .file else {
            // For a directory the only honest statement is what this test did to it, and the ledger is the record of that.
            #expect(room.ledger.hasEnumerated(url) == wasEnumerated, "The record of whether this directory was entered does not match what the precondition asked for.")

            guard level == .materializedDeep else {
                return nil
            }

            // What separates this level from a merely entered directory: the children hold their bytes. Asserted on the children rather than on the folder, because a directory has no content of its own to occupy blocks.
            for child in try room.localChildren(of: path) where child.kind == .file {
                #expect(child.allocatedBlocks > 0, "\"\(child.name)\" holds no content, so the folder was entered rather than deeply materialized.")
            }

            return nil
        }

        // An empty file is the one case where realization cannot be read from the file system. There is nothing to fetch, so the dataless flag is never cleared and the allocated blocks never rise above zero: a placeholder and a materialized copy of an empty file are the same three numbers. The cell is still worth running — every other clause holds — so the state is declined rather than the cell excluded.
        guard scenario.item.size != .empty else {
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.emptyFileReason)

            return try await room.remoteFingerprint(of: remotePath)
        }

        // An evicted file and one which was never fetched present the same size, the same flag and the same zero blocks — measured, and the reason this level was excluded until now. What differs is the item's history, which the file system does not record, so the state is confirmed as far as it can be and the distinction is declined rather than asserted.
        if level == .evicted {
            ScenarioOracle.decline("realizationState", because: ScenarioOracle.evictedItemReason)
        }

        guard level == .materialized else {
            // Awaited together rather than read once: these do not settle at the same instant, and reading one of them early is how a placeholder reports a size it does not yet have.
            try await Waiter.waitUntilBlocking("\(scenario.item.kind.rawValue) \"\(url.lastPathComponent)\" settles as a placeholder", timeout: LiveEnvironment.scaled(.seconds(60))) {
                guard let node = try LocalNode.at(url) else {
                    return false
                }

                return node.isDataless && node.size == Int64(bytes(for: scenario.item.size) ?? smallFileSize) && node.allocatedBlocks == 0
            }

            return nil
        }

        #expect(!node.isDataless, "The file was asked to be materialized and is still a placeholder.")

        // The full path, not the last component. A bare name resolves at the domain root and nowhere else, so reading it this way worked for every cell at `at:standard:root` and failed for every cell in a subdirectory — which is the shape of mistake a matrix finds and a hand-written test, always at the root, never can.
        return try await room.remoteFingerprint(of: remotePath)
    }
}
