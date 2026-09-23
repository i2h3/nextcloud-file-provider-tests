// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ScenarioMatrix
import ServerHarness
import Synchronization
import Testing

///
/// Judges what happened to a scenario's subject, and declines to judge what it cannot see.
///
/// The model gives every cell a set of oracle clauses. This evaluates the ones this harness can actually observe and **records the rest as declined**, by name and with a reason, rather than implementing them as something that happens to pass.
///
/// That distinction is the reason this type exists at all. Two of the clauses on every cell in this quadrant cannot fail as written against what a test process can see: "exactly one item per name" is a property a POSIX directory enforces by itself, so asserting it over a listing is asserting that the file system works; and content-policy inheritance for an unpinned item reduces to "it was not spontaneously materialized", which is the realization check under a second name. Writing either would add a green tick to every run and cover nothing, which is worse than a gap, because a gap is visible.
///
enum ScenarioOracle {
    ///
    /// A clause which was not evaluated, and why.
    ///
    struct Declined {
        ///
        /// The clause.
        ///
        let oracle: String

        ///
        /// Why it could not be judged here.
        ///
        let reason: String
    }

    ///
    /// Why "exactly one item per name" cannot be judged from a test process.
    ///
    /// Shared between suites rather than written out per quadrant: the reason is a property of what a test process can see, not of any one operation, and two copies of it would eventually disagree.
    ///
    static let posixListingReason = """
    A POSIX directory cannot hold two entries under one name, so reading a listing and finding one of each name asserts that the file system works rather than that the client does. Judging it needs the framework's own view of the replica, which a test process cannot reach.
    """

    ///
    /// Why content-policy inheritance cannot be judged on a cell with no pin anywhere.
    ///
    static let unpinnedReason = """
    Every cell here is unpinned, so the clause reduces to "the item was not materialized without being asked", which is the realization check under another name. Pinning cannot be set or read from a test process, so the inheritance this clause exists for is unreachable.
    """

    ///
    /// Why nothing can be pinned down about the realization of an item which has moved.
    ///
    static let movedItemReason = """
    A move pins the state of the two containers rather than of the item, and what a move does to an item's own realization is not specified — a placeholder which stays a placeholder and one which is fetched on arrival are both permitted. Asserting either would pin down something the system is free to decide.
    """

    ///
    /// Why nothing can be said about the realization of an item which no longer exists.
    ///
    static let deletedItemReason = """
    After a deletion there is no item left to be a placeholder or to be materialized, so any assertion about its realization reduces to asserting that it is gone — which is the consistency clause under another name, and is checked there.
    """

    ///
    /// Why the realization of an empty file cannot be read.
    ///
    static let emptyFileReason = """
    An empty file has nothing to fetch, so the dataless flag is never cleared and no blocks are ever allocated: a placeholder and a materialized copy present the same size, the same flag and the same zero blocks. Every signal this harness has for realization is blind here, and asserting either state would be asserting that an empty file is empty.
    """

    ///
    /// Why an evicted item cannot be told from one which was never fetched.
    ///
    static let evictedItemReason = """
    An evicted file and a placeholder which was never fetched present an identical triple to a test process: the dataless flag set, the size of the file they stand for, and no allocated blocks. The difference between them is the item's history — one has been through the provider and takes a re-fetch path — and nothing the file system exposes records that. The state is established and confirmed as far as it goes; which of the two it is cannot be asserted from here.
    """

    ///
    /// Why no winner can be named when both sides deleted the same item.
    ///
    static let mutualDeletionReason = """
    The permitted results of this clause — a conflict copy, the server's version winning, the local one winning — name which branch's content survived. A deletion on both sides leaves no content to attribute to a winner: a conflict copy would be visible, and its absence does not distinguish the other two from each other. Recording one of them would be a guess wearing the shape of an observation.
    """

    ///
    /// Why nothing can be pinned down about the realization of an item which has just been created.
    ///
    static let createdItemReason = """
    A create pins the state of the container rather than of the item, and the model says nothing about which state a newly created item should be in. Both answers are defensible — an item written in the client already has its bytes on disk, and one arriving from the server is free to be a placeholder or to be fetched — so asserting either would pin down something the system is entitled to decide.
    """

    ///
    /// Why the bytes of a trashed copy are out of reach.
    ///
    static let trashContentReason = """
    Comparing the bytes of the trashed copy needs a download against the server's trash endpoint, which the WebDAV client used here does not expose. Its recorded size is asserted instead, which catches a truncated or empty copy but not a corrupted one.
    """

    ///
    /// Judge whether the container holds one item per name, where that is a question a test process can answer.
    ///
    /// For most cells it is not, and the clause is declined: a POSIX directory cannot hold two entries under one name, so reading a listing and finding one of each asserts that the file system works.
    ///
    /// The encoding cells are the exception, and the reason the axis exists at all. Precomposed and decomposed forms of the same name are **different byte sequences**, so a directory can hold both — and it will, if the client compares the name it received against the name on disk without normalising either side. That is not hypothetical: macOS writes decomposed and a Nextcloud server stores what it was sent, so an asymmetric policy shows up as a second copy of a file somebody already has.
    ///
    /// A name which differs only by case is the same question on a volume which folds case, where the two cannot coexist and one has to give way.
    ///
    /// - Parameters:
    ///     - cell: The cell, whose encoding says whether this is answerable.
    ///     - name: The name the item was given.
    ///     - parentLocalPath: The container to read, relative to the domain.
    ///     - room: The room.
    ///
    static func judgeDuplicates(for cell: Scenario, named name: String, under parentLocalPath: String, in room: CleanRoom) {
        guard cell.encoding != nil else {
            decline("noDuplicatesOrOrphans", because: posixListingReason)

            return
        }

        guard let entries = try? room.localChildren(of: parentLocalPath) else {
            decline("noDuplicatesOrOrphans", because: "the container could not be listed, so nothing about what it holds follows")

            return
        }

        // Compared in one form, because that is the comparison the clause is about. Counting raw bytes would find one of each and call a duplicate a pass.
        let wanted = name.precomposedStringWithCanonicalMapping
        let matching = entries.filter { $0.name.precomposedStringWithCanonicalMapping == wanted }

        #expect(matching.count <= 1, """
        The container holds \(matching.count) items whose names are the same once normalised, so a person sees the file twice. It holds: \(entries.map(\.name).sorted().joined(separator: ", ")). macOS writes decomposed names and the server stores what it was sent, so a comparison which does not normalise both sides reports two items where there is one — and then writes the second.
        """)
    }

    ///
    /// Record something a cell observed which it is not entitled to assert.
    ///
    /// Distinct from a decline, which says a clause could not be judged, and from an expectation, which says what had to hold. This is the third thing a run produces: a legal outcome worth seeing, where the specification or the machine permits more than one and demanding either would make the cell fail somewhere reasonable.
    ///
    /// Printed once per occurrence rather than once per run, because the same cell can observe different things on different machines and the value is in knowing which happened here.
    ///
    /// Attached as well as printed. An observation which only reaches the terminal is gone by the time anyone opens the artifacts, and what the encoding axis exists to find out — whether this volume held both names or renamed one — would then be a thing the run knew and did not keep.
    ///
    /// - Parameters:
    ///     - observation: What happened.
    ///     - room: The room it happened in, which is what ties it to a cell.
    ///
    static func observe(_ observation: String, in room: CleanRoom) {
        print("  observed: \(observation)")

        let record = Observation(text: observation, user: room.user.identifier)

        guard let data = try? JSONEncoder().encode(record) else {
            return
        }

        Attachment.record(data, named: "\(room.user.identifier)-\(UUID().uuidString.prefix(8))\(Observation.attachmentSuffix)")
    }

    ///
    /// Record where a deleted item went, for a cell whose server keeps no trash.
    ///
    /// With the trash disabled the API gives no contract for the destination — the system decides, and it is explicitly not guaranteed — so this records rather than asserts. What it must not do is turn a failed look into an answer.
    ///
    /// It did. The trash was read as `(try? await room.server.trash()) ?? []`, which makes "the trash could not be read" and "the item was not in the trash" the same empty array and records both as `removedPermanently`. On a server with the trash application disabled the endpoint may legitimately refuse, so the read failing is expected — which is exactly why the two had to be told apart rather than merged: the expected failure was covering for any other.
    ///
    /// Shared by the three delete quadrants, which each held their own copy of it.
    ///
    /// - Parameters:
    ///     - name: The item which was deleted.
    ///     - cell: The cell, which carries the contract.
    ///     - room: The room.
    ///
    static func judgeTrashPlacement(of name: String, for cell: Scenario, in room: CleanRoom) async {
        guard let remains = try? await room.server.trash() else {
            observe("""
            the trash could not be read after "\(name)" was deleted, so where it went was not observed. With the trash application disabled this may be the server refusing an endpoint it does not serve, which is why it is not recorded as the item having been removed permanently
            """, in: room)

            return
        }

        UnderdeterminedOutcome.observed(
            remains.contains { $0.name == name } ? "providerDefinedDestination" : "removedPermanently",
            for: .trashPlacement,
            in: cell,
            room: room
        )
    }

    ///
    /// Which clauses have already been reported in this run, and with which reason.
    ///
    /// A declined clause is usually a property of the suite rather than of a case: it is declined for the same reason every time, and a generated suite runs the same case body dozens of times. Printing it per case buries the run in two identical paragraphs per case — which is not merely noisy, it teaches a reader to skim exactly the part that says what is not covered.
    ///
    /// Keyed on the clause *and* the reason, because "usually" is not "always" and the key used to be the clause alone. A clause declined for one reason early in a run and for a different reason later — the second being the interesting one, and possibly a real failure wearing a decline's clothing — printed only the first. The premise that the reason never varies was written in this comment and enforced nowhere.
    ///
    private static let reported = Mutex<Set<String>>([])

    ///
    /// Say once, for the whole run, that a clause cannot be judged here.
    ///
    /// Said rather than left out. A clause quietly missing from an evaluation is indistinguishable from a clause that passed, which is the whole reason this is printed at all.
    ///
    /// - Parameters:
    ///     - oracle: The clause.
    ///     - reason: Why it cannot be judged.
    ///
    static func decline(_ oracle: String, because reason: String) {
        let isFirst = reported.withLock { $0.insert("\(oracle)\u{1F}\(reason)").inserted }

        guard isFirst else {
            return
        }

        let sentence = "\(oracle) — \(reason.replacingOccurrences(of: "\n", with: " "))"

        print("  not judged: \(sentence)")

        // Attached as well, and attached to the run rather than to a room. The reason is the same in every cell carrying the clause, so this belongs beside the run's totals — and a decline which only reaches the terminal is the one statement a reader most needs and least often has: it is what stands between a green row and the conclusion that everything about that cell was checked.
        let record = Observation(text: sentence, user: nil, isDecline: true)

        guard let data = try? JSONEncoder().encode(record) else {
            return
        }

        Attachment.record(data, named: "run-\(UUID().uuidString.prefix(8))\(Observation.attachmentSuffix)")
    }

    ///
    /// Wait for the rename to reach the client, then judge that it arrived completely.
    ///
    /// Both halves are checked, and the second is the one that matters. A new name appearing says the rename was applied; the old name being gone is what says it was applied *as a rename* rather than as a copy — and a duplicate left behind is precisely the defect this quadrant would be expected to find.
    ///
    /// Observed by `lstat` on the two paths rather than by listing the container. Listing would answer the same question, but it would also be the only enumeration some of these cells ever receive, and a cell whose precondition is "never entered" cannot be judged by entering it.
    ///
    /// - Parameters:
    ///     - subject: What was renamed.
    ///     - name: The name it was renamed to.
    ///     - room: The room.
    ///     - timeout: How long the client is given.
    ///
    /// - Returns: The item at its new path.
    ///
    /// - Throws: ``WaitTimeoutError`` if it never arrives, or whatever inspection raises.
    ///
    static func awaitRename(of subject: ScenarioSubject, to name: String, in room: CleanRoom, timeout: Duration) async throws -> LocalNode {
        let oldURL = room.localURL(of: subject.localPath(of: subject.name))
        let newURL = room.localURL(of: subject.localPath(of: name))

        try await Waiter.waitUntilBlocking("the rename of \"\(subject.name)\" to \"\(name)\" reaches the client", timeout: timeout) {
            try LocalNode.at(newURL) != nil && LocalNode.at(oldURL) == nil
        }

        return try #require(try LocalNode.at(newURL), "The renamed item vanished between the wait and the reading of it.")
    }

    ///
    /// Judge that the two sides agree about where the item is.
    ///
    /// - Parameters:
    ///     - subject: What was renamed.
    ///     - name: The name it was renamed to.
    ///     - room: The room.
    ///
    /// - Throws: Whatever reading the server raises.
    ///
    static func checkConsistency(of subject: ScenarioSubject, renamedTo name: String, in room: CleanRoom) async throws {
        let remote = try await room.remoteChildren(of: subject.parentRemotePath)
        let names = remote.map(\.name).sorted()

        #expect(names.contains(name), """
        The server does not hold the renamed item. It holds: \(names.joined(separator: ", ")).
        """)

        #expect(!names.contains(subject.name), """
        The server still holds the item under its old name "\(subject.name)" as well as its new one, so the rename left a duplicate behind. It holds: \(names.joined(separator: ", ")).
        """)
    }

    ///
    /// Judge that a rename did not change how much of the item is on disk.
    ///
    /// Only for files, and deliberately. `SF_DATALESS` on a directory encodes whether its contents have been fetched, and nothing specifies what a rename does to that — so asserting it for a directory would be pinning down something the system is free to do either way.
    ///
    /// - Parameters:
    ///     - node: The item after the rename.
    ///     - scenario: The cell.
    ///     - expected: The level the precondition established.
    ///
    static func checkRealizationState(_ node: LocalNode, scenario: Scenario, expected: RealizationLevel) {
        guard scenario.item.kind == .file else {
            return
        }

        switch expected {
            case .dataless, .evicted:
                // Evicted is judged here and used to fall through the default into nothing. An evicted file is dataless — the content was fetched and then dropped — so the claim holds for it and holds harder: the user asked for that space back, and a rename which fetches takes it away again over a change they did not make. The clause it could not carry is declined below rather than standing in for the one it can.
                #expect(node.isDataless, """
                Renaming the file on the server caused the client to fetch its content. A change of name is metadata, and materializing an item nobody asked for spends the user's bandwidth and disk on a rename.
                """)

                if expected == .evicted {
                    decline("realizationState", because: evictedItemReason)
                }

            case .materialized:
                #expect(!node.isDataless, """
                Renaming the file on the server caused the client to drop content it already had, so a rename costs the user the download again.
                """)

            case .materializedDeep, .unknown:
                // Said rather than skipped. A `default: break` here left the reader unable to tell a level this oracle chose not to judge from one it had forgotten, which is the difference between a stated limit and a hole — and `evictedItemReason` sat in this file, written for a case that reached `break`.
                decline("realizationState", because: """
                a file at \(expected.rawValue), which is not a state a plain file can be in: deep materialization describes a folder's children and `unknown` describes a container nothing has enumerated. Nothing is asserted about how much of it is on disk
                """)
        }
    }

    ///
    /// Judge that the item is still the same item on the server.
    ///
    /// Worth being exact about what this covers. The rename is performed over WebDAV, so a preserved `oc:fileid` is in the first instance a statement about the **server**, not about the client. It is asserted anyway, for two reasons: it is the precondition for the client-side property being meaningful at all, and an identity destroyed here takes the item's shares, favourites, comments and version history with it regardless of which side destroyed it.
    ///
    /// The client-side half — that the File Provider item identifier survived — is **not** asserted, because `NSFileProviderItem` is unreachable from a test process and no URL resource key exposes the identifier. See the declined clauses on any run of this suite.
    ///
    /// - Parameters:
    ///     - subject: What was renamed.
    ///     - name: The name it was renamed to.
    ///     - room: The room.
    ///
    /// - Throws: Whatever reading the server raises.
    ///
    static func checkIdentityStability(of subject: ScenarioSubject, renamedTo name: String, in room: CleanRoom) async throws {
        let remote = try await room.remoteChildren(of: subject.parentRemotePath)

        guard let after = remote.first(where: { $0.name == name }) else {
            return
        }

        #expect(after.fileIdentifier == subject.before.fileIdentifier, """
        The rename gave the item a new identity on the server: it was \(subject.before.fileIdentifier ?? "unknown") and is now \(after.fileIdentifier ?? "unknown"). Everything hanging from the old identity — shares, favourites, comments, the version history — belongs to an item which no longer exists, even though the name and the content are both correct.
        """)
    }

    ///
    /// Judge that the bytes did not change.
    ///
    /// Two comparisons, and the second is the one the clause is named for. The first reads the server before and after and says the rename did not disturb what it stored. The second reads the client and says the two sides agree — which is the only half that can catch a rename which quietly replaced the item with something else on one side only.
    ///
    /// The second half is taken only where taking it changes nothing. Reading a placeholder to compare its content is how the oracle creates the state it is measuring: on a File Provider item, opening is fetching. So it is read when the cell says the item was already materialized, and declined out loud otherwise.
    ///
    /// It used to be the first comparison alone, which is the server against itself. That is worth asserting and it is not this clause: a client which renamed the item and silently emptied its own copy passed it.
    ///
    /// - Parameters:
    ///     - subject: What was renamed.
    ///     - name: The name it was renamed to.
    ///     - cell: The cell, which says what the item is and how much of it was on disk.
    ///     - room: The room.
    ///
    /// - Throws: Whatever reading raises.
    ///
    static func checkContentMatch(of subject: ScenarioSubject, renamedTo name: String, for cell: Scenario, in room: CleanRoom) async throws {
        guard let fingerprint = subject.fingerprint else {
            return
        }

        let stored = try await room.remoteFingerprint(of: subject.remotePath(of: name))

        #expect(stored == fingerprint, "The content of the item changed during a rename, which alters only its name.")

        guard case let .item(level) = cell.realization, level == .materialized, cell.item.kind == .file else {
            decline("contentMatch", because: """
            it compares the server with itself here. The client's copy is only read where reading it changes nothing, and this cell \(cell.item.kind == .file ? "asks for an item which is not materialized, so opening it to compare would fetch it" : "is not a plain file, whose bytes do not live at one path")
            """)

            return
        }

        let url = room.localURL(of: subject.localPath(of: name))

        guard let data = try? Data(contentsOf: url) else {
            Issue.record("""
            The renamed item cannot be read in the client, although the cell had it materialized before the rename. A rename is metadata and must leave the bytes where they were.
            """)

            return
        }

        #expect(ContentFactory.fingerprint(of: data) == stored, """
        The client and the server disagree about the contents of "\(name)" after a rename which alters only a name. The server holds what it held before; the client holds something else.
        """)
    }
}
