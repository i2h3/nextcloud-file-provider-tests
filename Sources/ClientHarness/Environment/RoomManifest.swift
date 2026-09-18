// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What one clean room was, written beside the logs it left behind.
///
/// Without this a run's artifacts cannot be read. A clean room's directory is named after the Nextcloud user it created, which is derived from the short label a test passes when it asks for a room — and that label has nothing to do with the name of the test function. So a failure reported against `A file changed on both sides at once does not lose the server's version.` has no discoverable connection to the directory holding the only logs which could explain it.
///
/// The window matters as much as the name. Rooms are built one at a time and never overlap, which is enforced rather than assumed, so the room standing at the moment a test failed is unambiguously the room that test ran in.
///
/// Placing a moment in that window is deliberately not a method here. A thrown error is recorded after its room has been torn down, so `startedAt ... endedAt` excludes exactly the failures worth placing, and the rule needs the *next* room's start to be right. It lives with the rooms in ``RunEvidence/room(of:)``, where the whole ordered sequence is in hand. That is what makes it possible to attribute a failure to a server without the test framework telling anyone which argument it was running.
///
public struct RoomManifest: Codable, Sendable {
    ///
    /// The version of this file's own shape, so that a reader can tell an old manifest from a broken one.
    ///
    public let schemaVersion: Int

    ///
    /// The short label the test asked for the room under, such as `Conflict.simultaneousModification`.
    ///
    public let testName: String

    ///
    /// The identifier of the test which ran here, as the testing library names it.
    ///
    /// Optional because it is read from the testing library's notion of the test currently running, which is not guaranteed to be there. When it is absent the window is the only way back to the test, which is why the window is not optional.
    ///
    public let testIdentifier: String?

    ///
    /// The name of the test which ran here, as a person reads it.
    ///
    public let testDisplayName: String?

    ///
    /// The cell of the scenario matrix this room was built for.
    ///
    /// The room's directory is named after its Nextcloud user, which is derived from the test name and is coarser than the cell: a suite runs several cells through one test function, and two of them can differ only in axes the derived name has no room for. Recording the cell here is what lets a reader go from a failure to the logs of the room it happened in without inferring anything from the ordering.
    ///
    /// Absent for the hand-written suites, which are not generated from the matrix and have no cell.
    ///
    public let cell: String?

    ///
    /// The Nextcloud user created for this room, which is also the name of its directory.
    ///
    public let user: String

    ///
    /// The server this room ran against.
    ///
    public let server: RunManifestServer

    ///
    /// Where the File Provider domain of this room was mounted.
    ///
    public var domainPath: String?

    ///
    /// The identifiers of the domains whose logs were kept.
    ///
    public var domainIdentifiers: [String]

    ///
    /// When the room began to be built.
    ///
    public let startedAt: Date

    ///
    /// When the room was torn down, if it was.
    ///
    public var endedAt: Date?

    ///
    /// The name of the file a manifest is written to inside a clean room's directory.
    ///
    public static let fileName = "room.json"

    ///
    /// Write the manifest into a clean room's directory.
    ///
    /// - Parameters:
    ///     - directory: The clean room's directory.
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
    /// Read the manifest of a clean room, if it has one.
    ///
    /// - Parameters:
    ///     - directory: The clean room's directory.
    ///
    /// - Returns: The manifest, or `nil` if there is none to read.
    ///
    public static func read(from directory: URL) -> RoomManifest? {
        guard let data = try? Data(contentsOf: directory.appending(path: fileName, directoryHint: .notDirectory)) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(RoomManifest.self, from: data)
    }

    ///
    /// Describe a clean room.
    ///
    /// - Parameters:
    ///     - testName: The short label the room was asked for under.
    ///     - testIdentifier: The identifier of the running test, if the testing library offers one.
    ///     - testDisplayName: The name of the running test as a person reads it.
    ///     - user: The Nextcloud user created for the room.
    ///     - server: The server the room runs against.
    ///     - startedAt: When the room began to be built. Defaults to now.
    ///
    public init(testName: String, cell: String? = nil, testIdentifier: String? = nil, testDisplayName: String? = nil, user: String, server: RunManifestServer, startedAt: Date = Date()) {
        domainIdentifiers = []
        schemaVersion = 1
        self.cell = cell
        self.server = server
        self.startedAt = startedAt
        self.testDisplayName = testDisplayName
        self.testIdentifier = testIdentifier
        self.testName = testName
        self.user = user
    }
}
