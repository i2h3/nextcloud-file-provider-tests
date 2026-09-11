// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Writes a draft bug report out as Markdown.
///
/// The sections come in the order the bug template of the destination repository asks for them, so that the document is pasted field by field rather than rewritten.
///
/// Everything is prose and everything is expanded. There is no block of the same facts repeated as data at the end: anything reading this can take them from the text, which is where a person reads them too, and a second copy is only a second thing to keep in step. Nothing is folded away behind a disclosure element either — a reader should see the whole document at once rather than discover that part of it was hidden.
///
public enum BugReportRenderer {
    ///
    /// Render a report.
    ///
    /// - Parameters:
    ///     - report: What to render.
    ///     - runIdentifier: The run it came from.
    ///     - secrets: Values which must not appear in the result.
    ///
    /// - Returns: The Markdown.
    ///
    public static func render(_ report: BugReport, runIdentifier: String, secrets: [String] = []) -> String {
        var lines = [String]()

        lines.append("> Drafted from run `\(runIdentifier)` by an end-to-end test suite. Read it before filing it.")
        lines.append("")

        appendDescription(to: &lines, report: report)
        appendReproduction(to: &lines, report: report)
        appendExpectation(to: &lines, report: report)
        appendAffectedFiles(to: &lines, report: report)
        appendEnvironment(to: &lines, report: report)
        appendEvidence(to: &lines, report: report)

        return Redaction.apply(to: lines.joined(separator: "\n"), secrets: secrets)
    }

    ///
    /// What the defect is, in the words of whoever wrote the test.
    ///
    /// Nothing is composed here. An expectation in this suite carries a comment saying what must not happen, written by a person at the time the test was written, and that sentence describes the defect better than anything assembled afterwards could. Quoting it is not the same as generating it.
    ///
    private static func appendDescription(to lines: inout [String], report: BugReport) {
        lines.append(report.summary)
        lines.append("")
    }

    ///
    /// What a maintainer needs to see it happen themselves.
    ///
    private static func appendReproduction(to lines: inout [String], report: BugReport) {
        lines.append("## Steps to reproduce")
        lines.append("")
        lines.append("Found by an automated end-to-end suite, which reproduces it on demand:")
        lines.append("")
        lines.append("```bash")
        lines.append("swift run tests --tags \(report.room?.server.tag ?? "latest") --filter \(suiteName(of: report.failure))")
        lines.append("```")
        lines.append("")

        if let location = report.failure.sourceLocation {
            lines.append("The assertion is at `\(location)`.")
            lines.append("")
        }
    }

    ///
    /// Both halves of what a bug is, and neither of them invented.
    ///
    private static func appendExpectation(to lines: inout [String], report: BugReport) {
        // Only the name of the test. What the expectation said about the failure is the description, and saying it twice trains a reader to skip one of them.
        lines.append("## Expected behavior")
        lines.append("")
        lines.append(report.failure.testDisplayName ?? report.summary)
        lines.append("")

        lines.append("## What happened instead")
        lines.append("")
        lines.append("```")
        lines.append(report.failure.message)
        lines.append("```")
        lines.append("")
    }

    ///
    /// The template asks which files are affected, and the expectation usually names them.
    ///
    private static func appendAffectedFiles(to lines: inout [String], report: BugReport) {
        lines.append("## Which files are affected")
        lines.append("")

        let named = subjects(of: report.failure)
        lines.append(named.isEmpty ? "—" : named.map { "`\($0)`" }.joined(separator: ", "))
        lines.append("")
    }

    ///
    /// The block a maintainer's first reply always asks for, filled in so that nobody has to.
    ///
    private static func appendEnvironment(to lines: inout [String], report: BugReport) {
        lines.append("## Environment")
        lines.append("")
        lines.append("| | |")
        lines.append("| --- | --- |")
        lines.append("| Operating system | macOS \(report.manifest?.machine["operatingSystem"] ?? "—") |")
        lines.append("| Desktop client | \(clientDescription(of: report)) |")
        lines.append("| Installation method | Signed build in `/Applications`, launched once by hand |")

        if let server = report.room?.server {
            lines.append("| Nextcloud Server | \(server.versionString ?? server.tag) (image tag `\(server.tag)`\(server.isPushEnabled ? ", with the High Performance Backend" : "")) |")
        }

        if let caseName = report.failure.caseDisplayName {
            lines.append("| Failing matrix entry | `\(caseName)` |")
        }

        // What the run verified about the machine before it started. Most of it is unremarkable, and that is the point: it answers the questions a maintainer would otherwise have to ask before believing the rest.
        for check in report.manifest?.preflight.checks ?? [] where check.isSatisfied && !isAlreadyDescribed(check) {
            lines.append("| \(check.subject) | \(check.detail) |")
        }

        lines.append("")

        // Not a property of the machine but of how the suite runs, and worth one sentence because it forecloses the first alternative explanation anybody reaches for.
        var isolation = "Tests run one at a time, and a clean room refuses to be built while another stands, so nothing else was touching the client or the server."

        if let room = report.room {
            isolation += " The account, its File Provider domain and its server user were created for this test alone and shared with nothing (`\(room.user)`)."
        }

        lines.append(isolation)
        lines.append("")

        if !report.hasCaseAttribution {
            lines.append("> This run recorded no event stream, so which entry of the matrix failed could not be established. The table above describes the run, not necessarily the failing entry.")
            lines.append("")
        }
    }

    ///
    /// What the File Provider actually did, which is the half of the story the client's own log does not contain.
    ///
    private static func appendEvidence(to lines: inout [String], report: BugReport) {
        lines.append("## Evidence")
        lines.append("")

        guard !report.excerpt.isEmpty else {
            lines.append("The File Provider extension left no log for this test.")
            lines.append("")

            return
        }

        lines.append("From the File Provider extension's own log, around the failure:")
        lines.append("")
        lines.append("```")

        for entry in report.excerpt {
            let described = entry.details.isEmpty ? "" : "  " + entry.details.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            lines.append("\(entry.level == "debug" ? " " : "*") [\(entry.category)] \(entry.message)\(described)")
        }

        lines.append("```")
        lines.append("")

        if report.omittedLines > 0 {
            lines.append("\(report.omittedLines) further lines were left out. Lines chosen by a heuristic, not by understanding the defect; the whole log is at `\(report.logPath ?? "the run's artifacts")`.")
            lines.append("")
        }
    }

    ///
    /// The name of the type holding the failing test, which is what narrows a run to it.
    ///
    /// The identifier reads `FileProviderTests.ConflictTests/`the test`(_:)/ConflictTests.swift:20:6`, so the type is the last part of the module path before the first slash. Taking the last dot-separated component of the whole thing yields the source location instead, which makes a command nobody can run.
    ///
    /// - Parameters:
    ///     - failure: The failure.
    ///
    /// - Returns: The type's name.
    ///
    public static func suiteName(of failure: ReportedFailure) -> String {
        let head = failure.testIdentifier.split(separator: "/").first.map(String.init) ?? failure.testIdentifier

        return head.split(separator: ".").last.map(String.init) ?? head
    }

    ///
    /// Whether a check is already said elsewhere in the table, so that it is not said twice.
    ///
    /// - Parameters:
    ///     - check: The check.
    ///
    /// - Returns: `true` if the environment already describes it.
    ///
    private static func isAlreadyDescribed(_ check: PreflightCheck) -> Bool {
        ["Desktop client", "System policy"].contains(check.subject)
    }

    ///
    /// How the client is described, including whether it was one a user would actually have.
    ///
    private static func clientDescription(of report: BugReport) -> String {
        let version = report.manifest?.preflight.checks.first { $0.subject == "Desktop client" }?.detail ?? "—"

        guard report.manifest?.preflight.checks.contains(where: { $0.subject == "System policy" && $0.detail.contains("REJECTED") }) == true else {
            return version
        }

        return "\(version) — a development build, which is not what a user installs"
    }

    ///
    /// The names the failure mentioned, which are the files it was about.
    ///
    /// - Parameters:
    ///     - failure: The failure.
    ///
    /// - Returns: The names, in the order they appeared.
    ///
    public static func subjects(of failure: ReportedFailure) -> [String] {
        let text = ([failure.message] + failure.comments).joined(separator: " ")
        let pattern = #"[A-Za-z0-9_\-. ]+\.(bin|txt|png|jpg|pdf|dat)"#

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var found = [String]()

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let name = String(text[range]).trimmingCharacters(in: .whitespaces)

            if !found.contains(name) {
                found.append(name)
            }
        }

        return found
    }
}
