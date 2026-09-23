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
}
