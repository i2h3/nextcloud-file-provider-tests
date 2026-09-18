// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Everything a finished run left behind, gathered into one place.
///
/// A run scatters its evidence: what failed is in one file, what the machine was is in another, and the logs which might explain it are in a directory named after a user whose name nothing else mentions. This puts them back together, and the joining is the only part which is not obvious.
///
/// A failure is attributed to a clean room by when it happened. Rooms are built one at a time and never overlap — which is enforced rather than hoped for — so the room whose life contains the moment of a failure is unambiguously the room that failure happened in. That works even when nothing else lines up, which is why the room records its window at all.
///
public struct RunEvidence: Sendable {
    ///
    /// The directory the run wrote to.
    ///
    public let directory: URL

    ///
    /// What the run was, if it said.
    ///
    public let manifest: RunManifest?

    ///
    /// What went wrong.
    ///
    public let failures: [ReportedFailure]

    ///
    /// The clean rooms of the run, in the order they were built.
    ///
    /// Ordered by when they began, which ``room(of:)`` depends on and the initializer guarantees.
    ///
    public let rooms: [RoomManifest]

    ///
    /// Whether the run recorded enough to say which case of a parameterized test failed.
    ///
    /// The xUnit report cannot, so a report drawn only from it has to admit as much rather than imply that the failure was not a parameterized one.
    ///
    public let hasCaseAttribution: Bool

    ///
    /// The zone the run happened in, which the extension's log needs and does not carry.
    ///
    public var timeZone: TimeZone {
        manifest.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
    }

    ///
    /// The room a failure happened in.
    ///
    /// - Parameters:
    ///     - failure: The failure to place.
    ///
    /// - Returns: The room, or `nil` if it cannot be placed.
    ///
    public func room(of failure: ReportedFailure) -> RoomManifest? {
        guard let occurredAt = failure.occurredAt else {
            // Read from the xUnit report, which carries no timestamps at all. A room knows which test asked for it, so an exact and unambiguous match is the only thing left — and a parameterized test has one room per case, so this almost never resolves.
            let candidates = rooms.filter { $0.testIdentifier == failure.testIdentifier }

            return candidates.count == 1 ? candidates.first : nil
        }

        // The room which was standing when the failure was recorded, where "standing" reaches to the moment the next room began rather than to the moment this one was torn down.
        //
        // The distinction is the whole of it. A thrown error is recorded by the testing library *after* the room it happened in has been torn down, so its moment lies a fraction of a second past the room's own `endedAt` and a window closed at `endedAt` can never contain it. That is not an edge case: it is every failure which throws rather than fails an expectation, which was all three in the run this was written for, each of them drafted with no log, no domain and no server named.
        //
        // Reaching to the next room's start is sound because rooms do not overlap — `CleanRoom.isOccupied` refuses to build a second one — so nothing else can have been running in the gap between one room's teardown and the next one's construction. The last room of a run is bounded by the run's own end instead, and by its teardown plus a grace if the run never recorded one.
        guard let index = rooms.lastIndex(where: { $0.startedAt <= occurredAt }) else {
            return nil
        }

        let room = rooms[index]
        let successor = rooms.indices.contains(index + 1) ? rooms[index + 1].startedAt : nil
        let runEnd = manifest.flatMap(\.finishedAt)

        guard let limit = successor ?? runEnd ?? room.endedAt?.addingTimeInterval(Self.teardownGrace) else {
            // A room which never recorded an end, in a run which never recorded an end either. Nothing bounds it, and a room that owns all later time would swallow failures belonging to nobody.
            return room
        }

        return occurredAt <= limit ? room : nil
    }

    ///
    /// How long after a room's teardown a failure may still be attributed to it.
    ///
    /// Only ever reached by the last room of a run whose own end went unrecorded. The interval is the gap between a room being torn down and the testing library recording the issue which caused it, which is the cost of writing the manifest and copying the logs — measured in fractions of a second, and given a margin here rather than a measurement.
    ///
    static let teardownGrace: TimeInterval = 60

    ///
    /// Gather what a run left behind.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///
    /// - Returns: The evidence.
    ///
    public static func gather(from directory: URL) -> RunEvidence {
        let events = directory.appending(path: EventStreamReader.fileName, directoryHint: .notDirectory)
        var failures = EventStreamReader.failures(in: events)
        var hasCaseAttribution = true

        if failures.isEmpty {
            // The event stream is produced by an option which is not documented, so a run may simply not have one. The xUnit report is always there and says less.
            failures = JUnitReader.failures(in: directory.appending(path: JUnitReader.fileName, directoryHint: .notDirectory))
            hasCaseAttribution = false
        }

        let roomsDirectory = directory.appending(path: "clean-rooms", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: roomsDirectory.path(percentEncoded: false))) ?? []

        let rooms = names
            .sorted()
            .compactMap { RoomManifest.read(from: roomsDirectory.appending(path: $0, directoryHint: .isDirectory)) }
            .sorted { $0.startedAt < $1.startedAt }

        return RunEvidence(
            directory: directory,
            manifest: RunManifest.read(from: directory),
            failures: failures,
            rooms: rooms,
            hasCaseAttribution: hasCaseAttribution && !failures.isEmpty
        )
    }

    ///
    /// The most recent run under a directory which got as far as reporting results.
    ///
    /// - Parameters:
    ///     - artifacts: The directory runs are collected in.
    ///
    /// - Returns: The run's directory, or `nil` if there is none.
    ///
    public static func mostRecentRun(in artifacts: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: artifacts.path(percentEncoded: false))) ?? []

        return names
            .sorted()
            .reversed()
            .map { artifacts.appending(path: $0, directoryHint: .isDirectory) }
            .first { directory in
                FileManager.default.fileExists(atPath: directory.appending(path: JUnitReader.fileName, directoryHint: .notDirectory).path(percentEncoded: false))
            }
    }

    ///
    /// Describe the evidence of a run.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///     - manifest: What the run was.
    ///     - failures: What went wrong.
    ///     - rooms: The clean rooms of the run, in any order.
    ///     - hasCaseAttribution: Whether it can be said which case failed.
    ///
    public init(directory: URL, manifest: RunManifest?, failures: [ReportedFailure], rooms: [RoomManifest], hasCaseAttribution: Bool) {
        self.directory = directory
        self.failures = failures
        self.hasCaseAttribution = hasCaseAttribution
        self.manifest = manifest
        // Sorted here rather than asked for sorted, because ``room(of:)`` reads one room's successor to know where it ends and would place failures in the wrong rooms, silently, given any other order. A caller which has its own order — the index sorts rooms by cell — then cannot break it by passing that order in.
        self.rooms = rooms.sorted { $0.startedAt < $1.startedAt }
    }
}
