// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Turns what a run left behind into draft reports on disk.
///
/// Reports are written inside the run's own directory, which is where they belong and — not incidentally — the only place they are safe. That directory is ignored by the repository on purpose: a draft describes a defect nobody has reported yet, and this repository is public. The check that it really is ignored is made before anything is written rather than trusted, because the cost of being wrong is permanent.
///
public enum BugReportWriter {
    ///
    /// The directory reports are collected in, inside a run.
    ///
    public static let directoryName = "reports"

    ///
    /// Draft a report for every failure of a run.
    ///
    /// Failures which the suite already knows about are skipped: they are being watched on purpose and are not news.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///     - isOverwriting: Whether a report which already exists may be replaced.
    ///
    /// - Returns: The files written, split by whether the run measured anything.
    ///
    /// - Throws: ``BugReportError`` if the reports would be written somewhere they could be committed.
    ///
    @discardableResult
    public static func write(for evidence: RunEvidence, isOverwriting: Bool = false) throws -> DraftedReports {
        let unknown = evidence.failures.filter { !$0.isKnown }

        guard !unknown.isEmpty else {
            return DraftedReports(conclusive: [], inconclusive: [], all: [])
        }

        let directory = evidence.directory.appending(path: directoryName, directoryHint: .isDirectory)
        try verifyIsIgnored(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written = [URL]()
        var conclusive = [URL]()
        var inconclusive = [URL]()

        for (index, group) in FailureGroup.group(unknown).enumerated() {
            let report = makeReport(for: group, evidence: evidence)
            let url = directory.appending(path: String(format: "%04d-%@.md", index + 1, report.slug), directoryHint: .notDirectory)

            // A report is generated once and then finished by hand. Replacing one without being asked would throw that work away.
            guard isOverwriting || !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }

            let rendered = BugReportRenderer.render(report, runIdentifier: evidence.manifest?.runIdentifier ?? evidence.directory.lastPathComponent, secrets: secrets(of: evidence))
            try Data(rendered.utf8).write(to: url, options: .atomic)
            written.append(url)

            if report.isConclusive {
                conclusive.append(url)
            } else {
                inconclusive.append(url)
            }
        }

        return DraftedReports(conclusive: conclusive, inconclusive: inconclusive, all: written)
    }

    ///
    /// Gather everything known about one failure.
    ///
    /// - Parameters:
    ///     - failure: The failure.
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The report.
    ///
    public static func makeReport(for failure: ReportedFailure, evidence: RunEvidence) -> BugReport {
        makeReport(for: FailureGroup(representative: failure, occurrences: [failure]), evidence: evidence)
    }

    ///
    /// Gather everything known about one defect, however many times the run saw it.
    ///
    /// The evidence is taken from the first occurrence rather than merged across all of them. Merging logs from four rooms would produce a document nobody can follow, and the occurrences are by construction the same failure — what they add is the comparison between matrix entries, which needs none of their logs.
    ///
    /// - Parameters:
    ///     - group: The failures which are one defect.
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The report.
    ///
    public static func makeReport(for group: FailureGroup, evidence: RunEvidence) -> BugReport {
        let failure = group.representative
        let room = evidence.room(of: failure)
        var entries = [ExtensionLogEntry]()
        var logPath: String?

        if let room, let log = newestLog(of: room, in: evidence) {
            entries = ExtensionLogEntry.read(from: log, timeZone: evidence.timeZone)
            logPath = log.path(percentEncoded: false).replacingOccurrences(of: evidence.directory.path(percentEncoded: false), with: "")
        }

        let selected = LogExcerpt.select(from: entries, failedAt: failure.occurredAt, subjects: BugReportRenderer.subjects(of: failure))

        return BugReport(
            failure: failure,
            room: room,
            manifest: evidence.manifest,
            excerpt: selected.lines,
            omittedLines: selected.omitted,
            logPath: logPath,
            hasCaseAttribution: evidence.hasCaseAttribution,
            occurrences: group.occurrences
        )
    }

    ///
    /// The extension log of a room, if it kept one.
    ///
    /// - Parameters:
    ///     - room: The room.
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The newest log file.
    ///
    private static func newestLog(of room: RoomManifest, in evidence: RunEvidence) -> URL? {
        let directory = evidence.directory
            .appending(path: "clean-rooms", directoryHint: .isDirectory)
            .appending(path: room.user, directoryHint: .isDirectory)
            .appending(path: "extension-logs", directoryHint: .isDirectory)

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
    }

    ///
    /// The values of a run which must never appear in a report.
    ///
    /// Deliberately empty for now, and worth explaining rather than leaving as an oversight. The obvious candidate is the name of each test user, because this suite makes a user's password the same string as its name. But that name is also the only way back from a report to the artifacts it came from — it names the directory holding the logs — and the account it belongs to lives inside a container which is deleted minutes later on somebody's own machine. Redacting it would cost the reader the thread back to the evidence and protect a credential which no longer has a server to be used against.
    ///
    /// What genuinely must never appear is the administrative password, and that is kept out by construction rather than by scrubbing: it is absent from every artifact a report reads. If a real server is ever tested against, this is the first thing which has to change.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The values.
    ///
    private static func secrets(of _: RunEvidence) -> [String] {
        []
    }

    ///
    /// Refuse to write anywhere the repository could pick it up.
    ///
    /// - Parameters:
    ///     - directory: Where the reports would go.
    ///
    /// - Throws: ``BugReportError/wouldBeCommittable(path:)`` if the repository does not ignore it.
    ///
    private static func verifyIsIgnored(_ directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["check-ignore", "-q", directory.path(percentEncoded: false)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // No git, no repository to commit to. Nothing to protect against.
            return
        }

        process.waitUntilExit()

        // Exit status 1 means git knows the path and does not ignore it. Anything else means git could not answer, which is not the same as an answer of no.
        guard process.terminationStatus == 1 else {
            return
        }

        throw BugReportError.wouldBeCommittable(path: directory.path(percentEncoded: false))
    }
}
