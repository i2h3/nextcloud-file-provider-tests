// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What a run was, written down so that its artifacts can still be read afterwards.
///
/// Everything here was already known while the run was happening and then thrown away: the preflight report went to the console, and the servers went into an environment variable of a process which has since exited. A run directory consequently records which tests failed but not which client or which server releases they failed against, which is the first thing anyone asks.
///
/// The time zone is recorded for an unglamorous but decisive reason: the File Provider extension writes its log with local timestamps and no zone, so reading those timestamps later requires knowing where the machine was.
///
public struct RunManifest: Codable, Sendable {
    ///
    /// The version of this file's own shape, so that a reader can tell an old manifest from a broken one.
    ///
    public let schemaVersion: Int

    ///
    /// The name of the run, which is also the name of its directory.
    ///
    public let runIdentifier: String

    ///
    /// When the run began.
    ///
    public let startedAt: Date

    ///
    /// When the run finished, if it did.
    ///
    public var finishedAt: Date?

    ///
    /// The identifier of the time zone the machine was in, such as `Europe/Berlin`.
    ///
    public let timeZoneIdentifier: String

    ///
    /// The offset from UTC in seconds at the time of the run.
    ///
    /// Recorded alongside the identifier because an identifier alone does not settle a timestamp which falls on a daylight saving transition.
    ///
    public let timeZoneOffsetSeconds: Int

    ///
    /// How the run was asked for.
    ///
    public let command: [String: String]

    ///
    /// What the machine was.
    ///
    public let machine: [String: String]

    ///
    /// What was verified about the machine before the run started.
    ///
    public let preflight: PreflightReport

    ///
    /// The servers the run was tested against.
    ///
    public var servers: [RunManifestServer]

    ///
    /// The name of the file a manifest is written to inside a run's directory.
    ///
    public static let fileName = "run.json"

    ///
    /// Facts about the machine which need no subprocess to establish.
    ///
    /// - Returns: The operating system release, its build and the architecture.
    ///
    public static func describeMachine() -> [String: String] {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        var described = [
            "operatingSystem": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "operatingSystemVersionString": ProcessInfo.processInfo.operatingSystemVersionString,
        ]

        #if arch(arm64)
            described["architecture"] = "arm64"
        #elseif arch(x86_64)
            described["architecture"] = "x86_64"
        #endif

        return described
    }

    ///
    /// Write the manifest into a run's directory.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///
    /// - Throws: Whatever encoding or writing raises.
    ///
    public func write(into directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(self).write(to: directory.appending(path: Self.fileName, directoryHint: .notDirectory), options: .atomic)
    }

    ///
    /// Read the manifest of a run, if it has one.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///
    /// - Returns: The manifest, or `nil` for a run recorded before manifests existed or one which never finished writing it.
    ///
    public static func read(from directory: URL) -> RunManifest? {
        guard let data = try? Data(contentsOf: directory.appending(path: fileName, directoryHint: .notDirectory)) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(RunManifest.self, from: data)
    }

    ///
    /// Describe a run.
    ///
    /// - Parameters:
    ///     - runIdentifier: The name of the run and of its directory.
    ///     - startedAt: When the run began. Defaults to now.
    ///     - timeZone: The time zone the machine is in. Defaults to the current one.
    ///     - command: How the run was asked for.
    ///     - preflight: What was verified about the machine.
    ///     - servers: The servers the run is tested against, which may be empty until they are deployed.
    ///
    public init(runIdentifier: String, startedAt: Date = Date(), timeZone: TimeZone = .current, command: [String: String], preflight: PreflightReport, servers: [RunManifestServer] = []) {
        self.command = command
        machine = Self.describeMachine()
        self.preflight = preflight
        self.runIdentifier = runIdentifier
        schemaVersion = 1
        self.servers = servers
        self.startedAt = startedAt
        timeZoneIdentifier = timeZone.identifier
        timeZoneOffsetSeconds = timeZone.secondsFromGMT(for: startedAt)
    }
}
