// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RunIndex``.
///
/// The run's front page is the artifact a person opens first and the only one written to be read rather than parsed, and until now nothing tested a line of it. That is the wrong way round: a report which renders a failure wrongly is a report which is believed wrongly, and every other artifact of a run is checked by something.
///
/// What is pinned here is the part where being wrong is silent — a quadrant heading derived from a string, a decline section which disappears when there is nothing to say, an escape which decides whether a failure message containing a `<` renders or breaks the page around it.
///
@Suite("Run index")
struct RunIndexTests {
    ///
    /// A server for the rooms to have run against.
    ///
    static let server = RunManifestServer(ServerUnderTest(
        tag: "latest",
        serverAddress: URL(string: "http://127.0.0.1:51658")!,
        containerIdentifier: "c0ffee",
        adminUser: "admin",
        adminPassword: "secret",
        isPushEnabled: false,
        versionString: "35.0.0"
    ))

    ///
    /// A room for a given cell.
    ///
    /// - Parameters:
    ///     - cell: The cell it ran, or `nil` for a hand-written suite which has none.
    ///     - testName: What the test was called.
    ///
    /// - Returns: The manifest.
    ///
    static func room(cell: String?, testName: String = "Remote.metadataUpdate") -> RoomManifest {
        RoomManifest(testName: testName, cell: cell, user: "user-\(abs(cell?.hashValue ?? testName.hashValue))", server: server)
    }

    ///
    /// A run made of the given rooms and nothing else.
    ///
    /// Rendered from a directory which does not exist, because everything under test here is assembled from the manifests rather than read off disk, and the parts which are read off disk degrade to empty rather than raising.
    ///
    /// - Parameters:
    ///     - rooms: The rooms.
    ///
    /// - Returns: The evidence.
    ///
    static func evidence(of rooms: [RoomManifest]) -> RunEvidence {
        RunEvidence(directory: URL(filePath: "/nonexistent/run"), manifest: nil, failures: [], rooms: rooms, hasCaseAttribution: true)
    }

    ///
    /// A quadrant is the first two words of a cell, which is its origin and its operation.
    ///
    @Test
    func `Cells are grouped by the quadrant their description opens with.`() {
        let grouped = RunIndex.group([
            Self.room(cell: "remote metadataUpdate item:dataless kind:file size:small at:standard:root"),
            Self.room(cell: "remote metadataUpdate item:materialized kind:folderEmpty at:standard:root"),
            Self.room(cell: "local delete item:dataless kind:file size:small at:standard:root trash:with"),
        ])

        #expect(grouped.keys.sorted() == ["local delete", "remote metadataUpdate"])
        #expect(grouped["remote metadataUpdate"]?.count == 2)
    }

    ///
    /// A hand-written suite has no cell, and must still land somewhere a reader can find it rather than under an empty heading.
    ///
    @Test
    func `A room with no cell is grouped by its suite instead.`() {
        let grouped = RunIndex.group([Self.room(cell: nil, testName: "Conflict.preserveLocalChanges")])

        #expect(grouped.keys.sorted() == ["Conflict"])
    }

    ///
    /// Nothing declined means no section, rather than a heading over an empty list which reads as "nothing was left unmeasured".
    ///
    @Test
    func `A run which declined nothing renders no section for it.`() {
        #expect(RunIndex.notJudged([]).isEmpty)
        #expect(RunIndex.notJudged([Observation(text: "both names are held", user: "some-room")]).isEmpty)
    }

    ///
    /// And a run which declined something says so, in its own words, with the count.
    ///
    @Test
    func `A declined clause is listed with what it said.`() {
        let markup = RunIndex.notJudged([
            Observation(text: "noDuplicatesOrOrphans — a POSIX listing cannot show two items of one name", user: nil, isDecline: true),
            Observation(text: "contentPolicyInheritance — a pin can be neither set nor read", user: nil, isDecline: true),
            Observation(text: "the local version won", user: nil),
        ])

        #expect(markup.contains("Not judged"))
        #expect(markup.contains("noDuplicatesOrOrphans"))
        #expect(markup.contains("contentPolicyInheritance"))
        #expect(markup.contains("<span class=\"pill\">2</span>"))

        // An observation is evidence and a decline is the absence of it. Only the second belongs here, and mixing them would let a reader take one for the other.
        #expect(!markup.contains("the local version won"))
    }

    ///
    /// A failure message is written by a person and goes into the page unchanged. One containing a `<` must render as text rather than as the start of a tag.
    ///
    @Test
    func `Text which looks like markup is escaped rather than rendered.`() {
        let escaped = RunIndex.escape("a <b> & \"c\" > d")

        #expect(escaped == "a &lt;b&gt; &amp; &quot;c&quot; &gt; d")
        #expect(!escaped.contains("<b>"))
    }

    ///
    /// The ampersand has to be replaced first or it eats the escapes which follow it.
    ///
    @Test
    func `An ampersand is not escaped twice.`() {
        #expect(RunIndex.escape("&lt;") == "&amp;lt;")
    }

    @Test(arguments: [
        (0.0, "less than a second"),
        (1.0, "1 second"),
        (59.0, "59 seconds"),
        (60.0, "1 minute"),
        (3661.0, "1 hour, 1 minute and 1 second"),
        (7320.0, "2 hours and 2 minutes"),
    ] as [(TimeInterval, String)])
    func `A length of time is spoken the way a person would say it.`(_ pair: (seconds: TimeInterval, spoken: String)) {
        #expect(RunIndex.spoken(pair.seconds) == pair.spoken)
    }

    ///
    /// A run directory which does not exist yields nothing rather than failing, because a report may be asked for before anything has been attached.
    ///
    @Test
    func `A run with no attachments yields no observations rather than failing.`() {
        let missing = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let found = RunIndex.observations(in: missing)

        #expect(found.byRoom.isEmpty)
        #expect(found.run.isEmpty)
    }

    ///
    /// Observations belonging to a room and to the run are separated on the way in, because they are rendered in different places and only one of them has a row to sit under.
    ///
    @Test
    func `Observations are split by whether they belong to a room or to the run.`() throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let attachments = directory.appending(path: "attachments", directoryHint: .isDirectory)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)

        let encoder = JSONEncoder()

        for (name, observation) in [
            ("a", Observation(text: "both names are held", user: "room-one", recordedAt: Date(timeIntervalSince1970: 2))),
            ("b", Observation(text: "the name was bounced", user: "room-one", recordedAt: Date(timeIntervalSince1970: 1))),
            ("c", Observation(text: "a clause was declined", user: nil, isDecline: true)),
        ] {
            try encoder.encode(observation).write(to: attachments.appending(path: "\(name)\(Observation.attachmentSuffix)", directoryHint: .notDirectory))
        }

        let found = RunIndex.observations(in: directory)

        #expect(found.run.count == 1)
        #expect(found.byRoom["room-one"]?.count == 2)

        // Oldest first, so a room's observations read in the order they happened rather than in whatever order the directory was listed.
        #expect(found.byRoom["room-one"]?.map(\.text) == ["the name was bounced", "both names are held"])
    }

    ///
    /// A page whose filter deletes the page.
    ///
    /// The rule shipped as `tbody tr:not([data-outcome])`, which a browser reads as every row the page has: a bare `<tr>` goes into an implicit `<tbody>`, so choosing an option hid all fourteen rows of the machine facts, all five of the legend which defines the words the page is about, and the table saying what else is in the directory. It looked right in a screenshot taken below the fold.
    ///
    /// Asserted as the absence of the broken selector rather than the presence of the correct one, because that is the mistake which is cheap to make again.
    ///
    @Test
    func `No filter rule reaches a row outside the cells.`() {
        let html = RunIndex.render(Self.evidence(of: [Self.room(cell: "remote delete item:dataless kind:file size:small at:standard:root trash:with")]))

        #expect(!html.contains("tbody tr:not("), "A filter rule matches every row of the page, which hides the facts, the legend and the footer the moment anything is selected.")
        #expect(html.contains("tr.cell:not("))
    }

    ///
    /// Every outcome the control offers is an outcome the rules hide for.
    ///
    @Test
    func `A filter rule exists for every outcome.`() {
        let html = RunIndex.render(Self.evidence(of: [Self.room(cell: "remote delete item:dataless kind:file size:small at:standard:root trash:with")]))

        for outcome in CellOutcome.allCases {
            #expect(html.contains("body[data-filter=\"\(outcome.rawValue)\"]"), "Nothing hides anything when \"\(outcome.rawValue)\" is chosen, so selecting it would empty the page and read as a run of nothing.")
        }
    }

    ///
    /// The heat map and the table describe the same cells.
    ///
    /// The square is a link, and a link to an identifier no row carries is a link which does nothing. Counted rather than eyeballed because the two are assembled in separate functions from the same ordering, which is exactly the arrangement that drifts.
    ///
    @Test
    func `Every square links to a row which exists.`() {
        let cells = [
            "remote delete item:dataless kind:file size:small at:standard:root trash:with",
            "remote delete item:materialized kind:bundle at:standard:root trash:with",
            "local create parent:materialized kind:folderEmpty at:standard:subdirectory",
        ]

        let html = RunIndex.render(Self.evidence(of: cells.map { Self.room(cell: $0) }))
        let targets = Self.matches(of: "href=\"#(cell-[^\"]+)\"", in: html)
        let identifiers = Set(Self.matches(of: "<tr id=\"(cell-[^\"]+)\"", in: html))

        #expect(targets.count == cells.count)
        #expect(identifiers.count == cells.count)

        for target in targets {
            #expect(identifiers.contains(target), "A square links to \"#\(target)\", which no row answers to.")
        }
    }

    ///
    /// A run against more than one server says which one a row belongs to.
    ///
    /// No cell description carries a server, so without this every label on the page appears once per server with nothing to tell them apart — and a defect on one release and not the other is the reason there is more than one.
    ///
    @Test
    func `A row names its server only when the run had more than one.`() throws {
        let cell = "remote delete item:dataless kind:file size:small at:standard:root trash:with"
        let alone = RunIndex.render(Self.evidence(of: [Self.room(cell: cell)]))

        #expect(!alone.contains("· latest"), "A run against one server gains nothing from repeating its name on every row.")

        let older = try RunManifestServer(ServerUnderTest(
            tag: "33",
            serverAddress: #require(URL(string: "http://127.0.0.1:51659")),
            containerIdentifier: "decaf",
            adminUser: "admin",
            adminPassword: "secret",
            isPushEnabled: false,
            versionString: "33.0.8"
        ))

        var second = Self.room(cell: cell)
        second = RoomManifest(testName: second.testName, cell: cell, user: "user-older", server: older)

        let both = RunIndex.render(Self.evidence(of: [Self.room(cell: cell), second]))

        #expect(both.contains("· latest"))
        #expect(both.contains("· 33"))
    }

    ///
    /// Substrings captured by a pattern.
    ///
    /// - Parameters:
    ///     - pattern: The expression, with one capture group.
    ///     - text: The text to search.
    ///
    /// - Returns: What the group captured, in order.
    ///
    static func matches(of pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)

        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
