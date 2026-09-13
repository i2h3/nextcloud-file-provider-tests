// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for the drafting of bug reports.
///
/// Two properties matter more than the wording. Everything a run can establish has to be written down, because a document full of prompts asking somebody to come back later is a chore rather than a report; and it must never be written where the repository could pick it up, because a draft describes a defect nobody has reported and this repository is public.
///
@Suite("Bug report")
struct BugReportTests {
    ///
    /// A failure shaped like the one this suite was built to find.
    ///
    static let failure = ReportedFailure(
        testIdentifier: "FileProviderTests.ConflictTests/`A file changed on both sides at once does not lose the server's version.`(_:)/ConflictTests.swift:20:6",
        testDisplayName: "A file changed on both sides at once does not lose the server's version.",
        caseDisplayName: "latest",
        message: "Expectation failed: fingerprints do not contain the remote one",
        comments: [
            "// The property this suite exists for.",
            "The version written on the server was replaced by the one written locally. The server now holds: contested.bin = 0227589ee99a.",
        ],
        sourceLocation: ReportedSourceLocation(fileIdentifier: "FileProviderTests/ConflictTests.swift", line: 81),
        occurredAt: Date(timeIntervalSince1970: 1_000_030)
    )

    ///
    /// A report of that failure, with nothing else known about the run.
    ///
    static func makeReport() -> BugReport {
        BugReport(failure: failure, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)
    }

    ///
    /// The title is taken from the sentence written beside the expectation, because that sentence is a person's own account of what went wrong and no generator improves on it. It also means writing a good comment is the same act as writing a good bug title.
    ///
    @Test
    func `The title comes from what the expectation said, not from the name of the test.`() {
        #expect(Self.makeReport().title == "The version written on the server was replaced by the one written locally.")
    }

    ///
    /// The title is a line and the description is a paragraph, so the description keeps what the title cut.
    ///
    @Test
    func `The description keeps everything the expectation said, not only its first sentence.`() {
        let summary = Self.makeReport().summary

        #expect(summary.contains("The server now holds: contested.bin"))
        #expect(!summary.contains("// The property"))
    }

    ///
    /// A comment which is only source commentary is not a description of anything.
    ///
    @Test
    func `A report with nothing but source commentary falls back to the name of the test.`() {
        let bare = ReportedFailure(testIdentifier: "A.B/c", testDisplayName: "Something holds.", message: "no", comments: ["// just a note"])
        let report = BugReport(failure: bare, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: false)

        #expect(report.title == "Something holds.")
        #expect(report.summary == "Something holds.")
    }

    ///
    /// The reproduction command has to be one somebody can actually run. Taking the last dot-separated part of the whole identifier yields the source location instead, which produced `--filter swift:20:6`.
    ///
    @Test
    func `The reproduction command names the suite rather than the source location.`() {
        #expect(BugReportRenderer.suiteName(of: Self.failure) == "ConflictTests")

        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")
        #expect(rendered.contains("--filter ConflictTests"))
        #expect(!rendered.contains("--filter swift"))
    }

    ///
    /// Everything which can be established from a run is written down. A heading with nothing under it, or a note asking somebody to come back and fill it, is not a report — it is a chore.
    ///
    @Test
    func `Nothing is left as a prompt for somebody to fill in later.`() {
        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")

        #expect(!rendered.contains("<!--"))
        #expect(!rendered.contains("TODO"))
        #expect(!rendered.contains("left empty"))
    }

    ///
    /// A reader should see the whole document at once rather than find that part of it was folded away.
    ///
    @Test
    func `Nothing is hidden behind a disclosure element.`() {
        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")

        #expect(!rendered.contains("<details"))
        #expect(!rendered.contains("<summary"))
    }

    ///
    /// The report opens with what the defect is. A title above it would only repeat the first sentence of it, and a heading over a report's own description names the obvious.
    ///
    @Test
    func `The report opens with the description rather than with a heading.`() {
        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")
        let body = rendered.split(separator: "\n", omittingEmptySubsequences: true).drop { $0.hasPrefix(">") }

        #expect(body.first?.hasPrefix("#") == false)
        #expect(!rendered.contains("## Bug description"))
    }

    ///
    /// Everything the run established about the machine belongs together. Split across two sections it reads as two different kinds of fact, which it is not.
    ///
    @Test
    func `What the run checked about the machine is part of the environment.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: [PreflightCheck(subject: "Docker", isSatisfied: true, detail: "server 29.4.0")])
        )

        let report = BugReport(failure: Self.failure, room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)
        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(rendered.contains("## Environment"))
        #expect(rendered.contains("| Docker | server 29.4.0 |"))
        #expect(!rendered.contains("rules out"))
    }

    ///
    /// A check whose content the table already states in its own words would otherwise appear twice.
    ///
    @Test
    func `A check the environment already describes is not repeated.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: [PreflightCheck(subject: "Desktop client", isSatisfied: true, detail: "34.0.50 at /Applications/Nextcloud.app/")])
        )

        let report = BugReport(failure: Self.failure, room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)
        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(rendered.components(separatedBy: "34.0.50 at").count == 2)
    }

    ///
    /// The description is not composed: it is the sentence the test's author wrote beside the expectation, which is also where the title comes from.
    ///
    @Test
    func `The bug description is what the expectation said.`() {
        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")

        #expect(rendered.contains("The version written on the server was replaced by the one written locally."))
        #expect(!rendered.contains("// The property this suite exists for."))
    }

    ///
    /// Markdown needs a blank line before a heading, and a section which runs into the next one renders as a single paragraph.
    ///
    @Test
    func `Every heading stands on its own.`() {
        let rendered = BugReportRenderer.render(Self.makeReport(), runIdentifier: "r")
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() where line.hasPrefix("## ") && index > 0 {
            #expect(lines[index - 1].isEmpty, "The heading \(line) has no blank line before it.")
        }
    }

    ///
    /// The template of the repository this is destined for asks which files are affected, and the expectation usually names them.
    ///
    @Test
    func `The files the failure was about are picked out of what it said.`() {
        #expect(BugReportRenderer.subjects(of: Self.failure) == ["contested.bin"])
    }

    ///
    /// A report drawn from the poorer artifact has to say so rather than implying the failure was not a parameterized one.
    ///
    @Test
    func `A report which cannot say which case failed admits it.`() {
        let report = BugReport(failure: Self.failure, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: false)

        #expect(BugReportRenderer.render(report, runIdentifier: "r").contains("no event stream"))
    }

    ///
    /// The one mistake here which cannot be taken back, because a commit outlives the file it added.
    ///
    @Test
    func `Reports are refused anywhere the repository would pick them up.`() throws {
        let directory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory).appending(path: "Sources", directoryHint: .isDirectory)

        let evidence = RunEvidence(directory: directory, manifest: nil, failures: [Self.failure], rooms: [], hasCaseAttribution: true)

        #expect(throws: BugReportError.wouldBeCommittable(path: directory.appending(path: BugReportWriter.directoryName, directoryHint: .isDirectory).path(percentEncoded: false))) {
            try BugReportWriter.write(for: evidence)
        }
    }

    ///
    /// A failure the suite is already watching on purpose is not news.
    ///
    @Test
    func `A failure which is already known is not drafted.`() throws {
        let known = ReportedFailure(testIdentifier: "A.B/c", message: "expected", isKnown: true)
        let evidence = RunEvidence(directory: URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory), manifest: nil, failures: [known], rooms: [], hasCaseAttribution: true)

        #expect(try BugReportWriter.write(for: evidence).isEmpty)
    }

    @Test
    func `A run with no event stream reads as no failures rather than failing.`() {
        #expect(EventStreamReader.failures(in: URL(filePath: "/nowhere/events.jsonl")).isEmpty)
    }

    ///
    /// The failure this suite actually produced, and the one a report must not dress up as a finding.
    ///
    /// Two conflict tests threw at their very first step, before any conflict could exist, and the run drafted two articulate bug reports about a contract neither of them reached. A test which could not build what it needed has said something about this suite, not about the client.
    ///
    @Test
    func `A test which threw before asserting anything is not reported as a defect.`() {
        let failure = ReportedFailure(
            testIdentifier: "FileProviderTests.ConflictTests/paused()",
            testDisplayName: "A change made while an item was paused does not overwrite a newer server version.",
            message: "Caught error: Pausing synchronisation of the item failed.",
            comments: ["The contract itself."],
            thrownError: "Pausing synchronisation of the item failed (ClientHarness.SyncControlFailure)"
        )

        let report = BugReport(failure: failure, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)

        #expect(!report.isConclusive)

        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(rendered.contains("**Not a bug report.**"))

        // The suite's own documentation standing in as a description of a defect is how the misleading reports read.
        #expect(!rendered.contains("The contract itself."))
        #expect(rendered.contains("Pausing synchronisation of the item failed"))
    }

    ///
    /// The ordinary case must keep reading the way it did, or the distinction is bought by spoiling the reports that matter.
    ///
    @Test
    func `A contradicted expectation is still reported as a defect.`() {
        let failure = ReportedFailure(
            testIdentifier: "FileProviderTests.ConflictTests/advertised()",
            testDisplayName: "The client says whether it can pause an item.",
            message: "Expectation failed: supportsPausing(file)",
            comments: ["The client does not advertise that an item's synchronisation can be paused."]
        )

        let report = BugReport(failure: failure, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)

        #expect(report.isConclusive)

        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(!rendered.contains("**Not a bug report.**"))
        #expect(rendered.contains("The client does not advertise that an item's synchronisation can be paused."))
    }

    ///
    /// The same trap as the thrown-error one, in a different slot and from a different source.
    ///
    /// A test in this suite is named for the property that should hold. Printing that name under a heading asking what went wrong states the opposite of what happened — directly above the *Expected behavior* section, which correctly prints the same sentence. Thirty-eight expectations in the live suite carry no written sentence, so this is the ordinary case rather than the rare one.
    ///
    @Test
    func `An expectation with no sentence beside it does not borrow the test's name as the defect.`() {
        let failure = ReportedFailure(
            testIdentifier: "FileProviderTests.ServerToClientTests/placeholder()",
            testDisplayName: "A file created on the server appears in the client as a placeholder.",
            message: "Expectation failed: placeholder.size == Int64(content.count)"
        )

        let report = BugReport(failure: failure, room: nil, manifest: nil, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true)

        #expect(report.writtenDescription == nil)

        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(rendered.contains("No sentence was written beside the expectation"))

        // Once, under "Expected behavior", where it is true. Never as the description of the defect.
        #expect(rendered.components(separatedBy: "A file created on the server appears in the client as a placeholder.").count - 1 == 1)
    }
}
