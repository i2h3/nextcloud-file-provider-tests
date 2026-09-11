// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RunManifest`` and ``RunManifestServer``.
///
/// The manifest exists so that a run's artifacts can still be read once the run is over, and it feeds a document destined for a public issue tracker. Both of those properties are pinned here: what it records, and what it must never record.
///
@Suite("Run manifest")
struct RunManifestTests {
    ///
    /// A server described the way the runner would describe it, with credentials it must not pass on.
    ///
    static let server = ServerUnderTest(
        tag: "latest",
        serverAddress: URL(string: "http://localhost:51658")!,
        containerIdentifier: "c0ffee",
        adminUser: "admin",
        adminPassword: "hunter2-do-not-publish",
        isPushEnabled: false,
        versionString: "34.0.3"
    )

    ///
    /// Run a body against a directory of its own, and take it away again afterwards.
    ///
    /// - Parameters:
    ///     - body: What to do with the directory.
    ///
    /// - Throws: Whatever creating the directory or the body raises.
    ///
    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try body(directory)
    }

    ///
    /// The reason ``RunManifestServer`` exists at all. `ServerUnderTest` is itself `Codable` and carries the administrative password, so writing one into an artifact would put a credential in a file which is quoted into a public bug report.
    ///
    @Test
    func `A described server carries no credentials.`() throws {
        let encoded = try JSONEncoder().encode(RunManifestServer(Self.server))
        let text = try #require(String(data: encoded, encoding: .utf8))

        #expect(!text.contains("hunter2-do-not-publish"))
        #expect(!text.contains("admin"))
        #expect(text.contains("34.0.3"))
    }

    ///
    /// The tag says what was asked for and the version says what answered, and a bug report needs the latter.
    ///
    @Test
    func `A described server keeps the release the server reported.`() {
        let described = RunManifestServer(Self.server)

        #expect(described.tag == "latest")
        #expect(described.versionString == "34.0.3")
        #expect(described.description == "latest")
    }

    @Test
    func `A server deployed with push notifications says so in its description.`() throws {
        let pushed = try ServerUnderTest(tag: "33", serverAddress: #require(URL(string: "http://localhost:1")), containerIdentifier: "x", adminUser: "admin", adminPassword: "x", isPushEnabled: true, versionString: "33.0.8")

        #expect(RunManifestServer(pushed).description == "33+push")
    }

    @Test
    func `A manifest survives being written and read back.`() throws {
        try Self.withDirectory { directory in
            var manifest = RunManifest(
                runIdentifier: "2026-09-11-130420",
                command: ["filter": "ConflictTests"],
                preflight: PreflightReport(checks: [PreflightCheck(subject: "Docker", isSatisfied: true, detail: "server 29.4.0")]),
                servers: [RunManifestServer(Self.server)]
            )
            manifest.finishedAt = Date()

            try manifest.write(into: directory)
            let read = try #require(RunManifest.read(from: directory))

            #expect(read.runIdentifier == "2026-09-11-130420")
            #expect(read.command["filter"] == "ConflictTests")
            #expect(read.preflight.checks.first?.subject == "Docker")
            #expect(read.servers.first?.versionString == "34.0.3")
            #expect(read.finishedAt != nil)
        }
    }

    ///
    /// The File Provider extension writes its log in local time with no zone at all, so reading those timestamps back later is impossible without knowing where the machine was.
    ///
    @Test
    func `A manifest records the time zone the run happened in.`() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let manifest = RunManifest(runIdentifier: "r", timeZone: zone, command: [:], preflight: PreflightReport(checks: []))

        #expect(manifest.timeZoneIdentifier == "Europe/Berlin")
        #expect(manifest.timeZoneOffsetSeconds == zone.secondsFromGMT(for: manifest.startedAt))
    }

    @Test
    func `A run which never wrote a manifest reads as none rather than failing.`() throws {
        try Self.withDirectory { directory in
            #expect(RunManifest.read(from: directory) == nil)
        }
    }

    ///
    /// A manifest written by an older harness has to stay readable, or a run's history becomes unreadable the first time a field is added.
    ///
    @Test
    func `A manifest without the newer optional fields still decodes.`() throws {
        try Self.withDirectory { directory in
            let minimal = """
            {
              "schemaVersion": 1,
              "runIdentifier": "2026-01-01-000000",
              "startedAt": "2026-01-01T00:00:00Z",
              "timeZoneIdentifier": "UTC",
              "timeZoneOffsetSeconds": 0,
              "command": {},
              "machine": {},
              "preflight": { "checks": [] },
              "servers": []
            }
            """

            try Data(minimal.utf8).write(to: directory.appending(path: RunManifest.fileName, directoryHint: .notDirectory))
            let read = try #require(RunManifest.read(from: directory))

            #expect(read.finishedAt == nil)
            #expect(read.servers.isEmpty)
        }
    }

    @Test
    func `The machine is described without running anything.`() {
        let described = RunManifest.describeMachine()

        #expect(described["operatingSystem"] != nil)
        #expect(described["architecture"] != nil)
    }
}
