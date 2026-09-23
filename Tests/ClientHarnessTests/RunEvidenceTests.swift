// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RunEvidence``.
///
/// What is pinned here is the placement of a failure in the clean room it happened in, because every other part of a report hangs off it: the server which was under test, the domain, the user, and the only logs which could explain anything.
///
/// The rule looks like a window check and is not one. A thrown error is recorded by the testing library *after* the room it happened in has been torn down, so its moment always lies just past that room's own end — and a run whose failures all throw is a run where a window closed at `endedAt` places nothing at all. That is not hypothetical: it is how three reports came to be drafted naming no room, no server and no log.
///
@Suite("Run evidence")
struct RunEvidenceTests {
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
    /// A room with a given window.
    ///
    /// - Parameters:
    ///     - user: What to call it, which is how the tests below tell them apart.
    ///     - startedAt: When it was built, as seconds since the epoch.
    ///     - endedAt: When it was torn down, as seconds since the epoch, or `nil` if it never was.
    ///
    /// - Returns: The manifest.
    ///
    static func room(_ user: String, from startedAt: TimeInterval, to endedAt: TimeInterval?) -> RoomManifest {
        var manifest = RoomManifest(
            testName: "Remote.metadataUpdate",
            testIdentifier: "FileProviderTests.RemoteMetadataUpdateTests/theTest(_:_:)",
            user: user,
            server: server,
            startedAt: Date(timeIntervalSince1970: startedAt)
        )

        manifest.endedAt = endedAt.map { Date(timeIntervalSince1970: $0) }

        return manifest
    }

    ///
    /// Evidence made of rooms and one failure at a given moment.
    ///
    /// - Parameters:
    ///     - rooms: The rooms, in the order they were built.
    ///     - occurredAt: When the failure was recorded, as seconds since the epoch, or `nil` for a failure read from the xUnit report.
    ///     - finishedAt: When the run ended, as seconds since the epoch, or `nil` if it never recorded one.
    ///
    /// - Returns: The evidence and the failure.
    ///
    static func evidence(rooms: [RoomManifest], occurredAt: TimeInterval?, finishedAt: TimeInterval? = nil) -> (RunEvidence, ReportedFailure) {
        let failure = ReportedFailure(
            testIdentifier: "FileProviderTests.RemoteMetadataUpdateTests/theTest(_:_:)",
            message: "Caught error: the cell's world could not be built",
            occurredAt: occurredAt.map { Date(timeIntervalSince1970: $0) }
        )

        var manifest: RunManifest?

        if let finishedAt {
            manifest = RunManifest(
                runIdentifier: "2026-09-18-113228",
                startedAt: Date(timeIntervalSince1970: 0),
                command: [:],
                preflight: PreflightReport(checks: [])
            )

            manifest?.finishedAt = Date(timeIntervalSince1970: finishedAt)
        }

        let evidence = RunEvidence(
            directory: URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory),
            manifest: manifest,
            failures: [failure],
            rooms: rooms,
            hasCaseAttribution: true
        )

        return (evidence, failure)
    }

    @Test
    func `A failure inside a room's own window belongs to that room.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200), Self.room("second", from: 210, to: 300)],
            occurredAt: 250
        )

        #expect(evidence.room(of: failure)?.user == "second")
    }

    ///
    /// The case the placement exists for, and the one a window closed at `endedAt` gets wrong.
    ///
    /// Every failure which throws lands here: the room is torn down, its manifest is written with the end it had, and only then does the testing library record the issue. A third of a second is what the real run showed between the two.
    ///
    @Test
    func `A failure recorded just after its room was torn down still belongs to it.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200), Self.room("second", from: 210, to: 300)],
            occurredAt: 300.34
        )

        #expect(evidence.room(of: failure)?.user == "second")
    }

    ///
    /// The gap between one room's teardown and the next one's construction belongs to the room which just ended, because nothing else can have been running in it.
    ///
    @Test
    func `A failure in the gap between two rooms belongs to the earlier one.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200), Self.room("second", from: 210, to: 300)],
            occurredAt: 205
        )

        #expect(evidence.room(of: failure)?.user == "first")
    }

    ///
    /// The next room's start is the hard boundary. Without it the last room of a run would own every later moment, and a failure belonging to nobody would be handed a room's logs to be explained by.
    ///
    @Test
    func `A failure after the next room began belongs to the next room, not the previous one.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200), Self.room("second", from: 210, to: 300)],
            occurredAt: 211
        )

        #expect(evidence.room(of: failure)?.user == "second")
    }

    @Test
    func `A failure before any room was built is placed nowhere.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200)],
            occurredAt: 50
        )

        #expect(evidence.room(of: failure) == nil)
    }

    ///
    /// The last room of a run is bounded by the run's own end, so a failure recorded after everything was packed up is not attributed to whichever room happened to be last.
    ///
    @Test
    func `A failure after the run finished is not attributed to its last room.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("only", from: 100, to: 200)],
            occurredAt: 5000,
            finishedAt: 400
        )

        #expect(evidence.room(of: failure) == nil)
    }

    @Test
    func `A failure within the run's life is attributed to the last room standing.`() {
        let (evidence, failure) = Self.evidence(
            rooms: [Self.room("only", from: 100, to: 200)],
            occurredAt: 250,
            finishedAt: 400
        )

        #expect(evidence.room(of: failure)?.user == "only")
    }

    ///
    /// A room whose teardown never finished, in a run whose end went unrecorded, is the one case with nothing to bound it. The grace covers the moment between the two, and a failure long afterwards is still refused rather than handed the wrong logs.
    ///
    @Test
    func `A room which never recorded its end is bounded by neither, and the grace decides.`() {
        let (near, nearFailure) = Self.evidence(rooms: [Self.room("only", from: 100, to: 200)], occurredAt: 230)
        #expect(near.room(of: nearFailure)?.user == "only")

        let (far, farFailure) = Self.evidence(rooms: [Self.room("only", from: 100, to: 200)], occurredAt: 5000)
        #expect(far.room(of: farFailure) == nil)

        let (open, openFailure) = Self.evidence(rooms: [Self.room("only", from: 100, to: nil)], occurredAt: 5000)
        #expect(open.room(of: openFailure)?.user == "only")
    }

    ///
    /// A failure read from the xUnit report has no moment at all, so only an unambiguous identity will do — and a parameterized test has one room per case, which is every test in this suite.
    ///
    @Test
    func `A failure without a moment is placed only when exactly one room claims its test.`() {
        let (ambiguous, ambiguousFailure) = Self.evidence(
            rooms: [Self.room("first", from: 100, to: 200), Self.room("second", from: 210, to: 300)],
            occurredAt: nil
        )

        #expect(ambiguous.room(of: ambiguousFailure) == nil)

        let (sole, soleFailure) = Self.evidence(rooms: [Self.room("only", from: 100, to: 200)], occurredAt: nil)
        #expect(sole.room(of: soleFailure)?.user == "only")
    }
}
