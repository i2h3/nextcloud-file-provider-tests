// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``FailureGroup``.
///
/// The behaviour being pinned here has a cost in both directions, which is why it is worth pinning at all. Grouping too eagerly hides a second defect behind the first. Grouping too little turns one defect into a report per server, which is how a real run produced sixteen documents describing two problems.
///
@Suite("Failure group")
struct FailureGroupTests {
    ///
    /// Build a failure the way a run produces one.
    ///
    /// - Parameters:
    ///     - message: What the expectation said.
    ///     - caseName: Which matrix entry it happened on.
    ///     - line: Where the expectation stands.
    ///
    /// - Returns: The failure.
    ///
    private func makeFailure(message: String, caseName: String, line: Int = 56) -> ReportedFailure {
        ReportedFailure(
            testIdentifier: "FileProviderTests.ConflictTests/advertised()",
            testDisplayName: "The client says whether it can pause an item.",
            caseDisplayName: caseName,
            message: message,
            sourceLocation: ReportedSourceLocation(fileIdentifier: "FileProviderTests/ConflictTests.swift", line: line)
        )
    }

    ///
    /// The case the matrix creates on every run, and the reason this type exists.
    ///
    /// The four messages differ only in the port the container happened to be assigned and the identifier of the room, neither of which says anything about the defect.
    ///
    @Test
    func `One defect seen on every server is one report.`() {
        let failures = [
            makeFailure(message: "Expectation failed: supportsPausing(file://~/Library/CloudStorage/Nextcloud-localhost:55295-conflict-408c15d2-021/advertised.bin)", caseName: "latest"),
            makeFailure(message: "Expectation failed: supportsPausing(file://~/Library/CloudStorage/Nextcloud-localhost:55301-conflict-91bf20a7-047/advertised.bin)", caseName: "latest+push"),
            makeFailure(message: "Expectation failed: supportsPausing(file://~/Library/CloudStorage/Nextcloud-localhost:55318-conflict-c40e11b9-083/advertised.bin)", caseName: "33"),
            makeFailure(message: "Expectation failed: supportsPausing(file://~/Library/CloudStorage/Nextcloud-localhost:55322-conflict-7ad9e0f2-119/advertised.bin)", caseName: "33+push"),
        ]

        let groups = FailureGroup.group(failures)

        #expect(groups.count == 1)
        #expect(groups.first?.occurrences.count == 4)
        #expect(groups.first?.matrixEntries == ["latest", "latest+push", "33", "33+push"])
    }

    ///
    /// Two expectations in the same test are two defects, even when both fail on every server.
    ///
    @Test
    func `Two expectations failing are two reports rather than one.`() {
        let groups = FailureGroup.group([
            makeFailure(message: "Expectation failed: supportsPausing(file)", caseName: "latest", line: 56),
            makeFailure(message: "Expectation failed: supportsFailingOnConflict(file)", caseName: "latest", line: 60),
        ])

        #expect(groups.count == 2)
    }

    ///
    /// One expectation can fail for two genuinely different reasons, and merging those would lose one of them.
    ///
    @Test
    func `The same expectation failing differently is not merged.`() {
        let groups = FailureGroup.group([
            makeFailure(message: "Expectation failed: the file was not there", caseName: "latest"),
            makeFailure(message: "Expectation failed: the file had the wrong content", caseName: "33"),
        ])

        #expect(groups.count == 2)
    }

    ///
    /// A report's number should say when its defect first appeared.
    ///
    @Test
    func `Groups keep the order their defects first appeared in.`() {
        let groups = FailureGroup.group([
            makeFailure(message: "Expectation failed: first", caseName: "latest", line: 10),
            makeFailure(message: "Expectation failed: second", caseName: "latest", line: 20),
            makeFailure(message: "Expectation failed: first", caseName: "33", line: 10),
        ])

        #expect(groups.map(\.representative.message) == ["Expectation failed: first", "Expectation failed: second"])
    }

    ///
    /// The comparison a maintainer reads first, and the one thing no individual failure can state.
    ///
    @Test
    func `A defect on some servers and not others is reported as exactly that.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: []),
            servers: [
                RunManifestServer(tag: "latest", versionString: "34.0.3"),
                RunManifestServer(tag: "latest", versionString: "34.0.3", isPushEnabled: true),
                RunManifestServer(tag: "33", versionString: "33.0.8"),
                RunManifestServer(tag: "33", versionString: "33.0.8", isPushEnabled: true),
            ]
        )

        let failing = [makeFailure(message: "Expectation failed", caseName: "latest"), makeFailure(message: "Expectation failed", caseName: "latest+push")]
        let report = BugReport(failure: failing[0], room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true, occurrences: failing)

        #expect(report.matrixDifferential?.failing == ["latest", "latest+push"])
        #expect(report.matrixDifferential?.passing == ["33", "33+push"])

        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(rendered.contains("Not affected: `33`, `33+push`"))
        #expect(rendered.contains("| Failing matrix entries | `latest`, `latest+push` |"))
    }

    ///
    /// The shape of a failure says something independent of what the failure says, and this suite has the worked example: sixteen failures uniform across four servers, all of them a broken reader and none of them the client.
    ///
    @Test
    func `A failure on every server at once is flagged as more likely the suite's fault.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: []),
            servers: [RunManifestServer(tag: "latest"), RunManifestServer(tag: "33")]
        )

        let failing = [makeFailure(message: "Expectation failed", caseName: "latest"), makeFailure(message: "Expectation failed", caseName: "33")]
        let report = BugReport(failure: failing[0], room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true, occurrences: failing)

        #expect(report.isUniformAcrossMatrix)
        #expect(BugReportRenderer.render(report, runIdentifier: "r").contains("Rule the suite out first."))
    }

    ///
    /// A defect which tracks the axis is the ordinary case and must not be flagged, or the flag means nothing.
    ///
    @Test
    func `A failure on some servers and not others is not flagged.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: []),
            servers: [RunManifestServer(tag: "latest"), RunManifestServer(tag: "33")]
        )

        let failure = makeFailure(message: "Expectation failed", caseName: "latest")
        let report = BugReport(failure: failure, room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true, occurrences: [failure])

        #expect(!report.isUniformAcrossMatrix)
        #expect(!BugReportRenderer.render(report, runIdentifier: "r").contains("Rule the suite out first."))
    }

    ///
    /// A comparison drawn from a matrix the run could not attribute failures within would be a false lead rather than a weak one.
    ///
    @Test
    func `Without case attribution no comparison is drawn.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: []),
            servers: [RunManifestServer(tag: "latest"), RunManifestServer(tag: "33")]
        )

        let failure = makeFailure(message: "Expectation failed", caseName: "latest")
        let report = BugReport(failure: failure, room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: false, occurrences: [failure])

        #expect(report.matrixDifferential == nil)
    }

    ///
    /// A comparison between two lists that are not about the same run states that nothing failed.
    ///
    @Test
    func `Case names the manifest does not know produce no comparison rather than an empty one.`() {
        let manifest = RunManifest(
            runIdentifier: "r",
            command: [:],
            preflight: PreflightReport(checks: []),
            servers: [RunManifestServer(tag: "latest"), RunManifestServer(tag: "33")]
        )

        // A name that matches no server — a renamed tag, an older manifest, a different spelling.
        let failure = makeFailure(message: "Expectation failed", caseName: "34")
        let report = BugReport(failure: failure, room: nil, manifest: manifest, excerpt: [], omittedLines: 0, logPath: nil, hasCaseAttribution: true, occurrences: [failure])

        #expect(report.matrixDifferential == nil)

        let rendered = BugReportRenderer.render(report, runIdentifier: "r")

        #expect(!rendered.contains("Not affected:"))
        #expect(!rendered.contains("Every server the run tested was affected."))
    }
}
