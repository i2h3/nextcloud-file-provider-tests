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

        if report.isConclusive {
            lines.append("> Drafted from run `\(runIdentifier)` by an end-to-end test suite. Read it before filing it.")
        } else {
            // The distinction the whole document turns on. A test which threw on its way to an expectation has shown that this suite could not carry out the measurement — which may be the client's fault, and may equally be the suite's, and is not evidence of either until somebody looks.
            lines.append("> **Not a bug report.** This test did not contradict an expectation — it raised an error before reaching one, so the run could not make the measurement it intended. That may be the client's doing or this suite's, and the document below is a record of a measurement which did not happen rather than of a defect. Establish which before treating any of it as a finding.")
            lines.append(">")
            lines.append("> Drafted from run `\(runIdentifier)`.")
        }

        lines.append("")

        // Placed here rather than in the environment because it changes whether the document is filed at all, and a reader who has reached the environment section has already decided.
        if report.isUniformAcrossMatrix {
            lines.append("> This failed on every server the run tested, which is worth a second look before filing. A defect in the client usually tracks something the matrix varies; one which does not track anything is as often a fault in the suite observing it. Rule the suite out first.")
            lines.append("")
        }

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
        guard let description = report.writtenDescription else {
            // Saying nothing is the honest answer, and it is also the actionable one: it names the thing that would have filled this in. Falling back to the name of the test here would print what *should* happen as though it were what went wrong.
            lines.append("No sentence was written beside the expectation that failed, so this run cannot say what the defect is — only what was asserted and what happened, both below. A comment beside the expectation is what fills this in, which makes writing one the same act as writing this paragraph.")
            lines.append("")

            return
        }

        lines.append(description)
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

        // The tag comes from the room or not at all. Defaulting to `latest` prints a complete, runnable, plausible command naming a matrix entry the run may never have deployed — and a maintainer who runs it and sees nothing concludes the report is wrong rather than that the command was invented.
        if let tag = report.room?.server.tag {
            lines.append("swift run tests --tags \(tag) --filter \(suiteName(of: report.failure))")
        } else {
            lines.append("swift run tests --filter \(suiteName(of: report.failure))")
        }

        lines.append("```")
        lines.append("")

        if report.room == nil {
            lines.append("This failure could not be placed in the clean room it happened in, so the command above runs the whole suite rather than the server this failure came from, and no log of the File Provider extension is quoted below.")
            lines.append("")
        }

        if let location = report.failure.sourceLocation {
            lines.append("The assertion is at `\(location)`.")
            lines.append("")
        }
    }

    ///
    /// Both halves of what a bug is, and neither of them invented.
    ///
    private static func appendExpectation(to lines: inout [String], report: BugReport) {
        // Only the name of the test, which is phrased as the property that should hold. Falling through to the description of the failure would print what went wrong under the heading asking what should have happened — the same inversion as the description slot, with the two swapped.
        lines.append("## Expected behavior")
        lines.append("")
        lines.append(report.failure.testDisplayName ?? "The run did not record the name of the test, so what it expected cannot be stated here.")
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
        // Deliberately not a constant any more. It read "Signed build in `/Applications`, launched once by hand" on every report ever drafted, in the same shape as the rows either side of it, which are measured — and it contradicted the row above it on every run started with the flag that accepts a development build.
        lines.append("| Installation method | \(installationDescription(of: report)) |")

        let entries = report.occurrences.compactMap(\.caseDisplayName)

        if entries.count > 1, let servers = report.manifest?.servers, !servers.isEmpty {
            // Naming the room's own server here would be wrong once the defect is known to span the matrix: it is the server of the first occurrence, not of the defect. The versions are what a maintainer needs; which entry is which is the row below.
            var versions = [String]()

            for server in servers where entries.contains(server.description) {
                let version = server.versionString ?? server.tag

                if !versions.contains(version) {
                    versions.append(version)
                }
            }

            lines.append("| Nextcloud Server | \(versions.joined(separator: ", ")) |")
        } else if let server = report.room?.server {
            lines.append("| Nextcloud Server | \(server.versionString ?? server.tag) (image tag `\(server.tag)`\(server.isPushEnabled ? ", with the High Performance Backend" : "")) |")
        }

        if !entries.isEmpty {
            lines.append("| Failing matrix \(entries.count == 1 ? "entry" : "entries") | \(entries.map { "`\($0)`" }.joined(separator: ", ")) |")
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

        // The comparison, which is the one thing the run knows that no single failure does.
        if let differential = report.matrixDifferential {
            if differential.passing.isEmpty {
                lines.append("Every server the run tested was affected.")
            } else {
                lines.append("The run tested more than one server and they did not agree. Affected: \(differential.failing.map { "`\($0)`" }.joined(separator: ", ")). Not affected: \(differential.passing.map { "`\($0)`" }.joined(separator: ", ")).")
            }

            lines.append("")
        }

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
        ["Desktop client"].contains(check.subject)
    }

    ///
    /// How the client under test came to be on this machine, as far as the run established it.
    ///
    /// Only the parts the preflight actually checked. Everything else about the installation — that somebody launched it once by hand, that it came from a release rather than a build directory — is true of how this suite is normally used and was never verified by the run holding the report.
    ///
    /// - Parameters:
    ///     - report: The report.
    ///
    /// - Returns: The description.
    ///
    private static func installationDescription(of _: BugReport) -> String {
        "Not established by this run. The client was already installed at the path above; this suite does not install it, and the signature and system-policy rows below are all it checked."
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
