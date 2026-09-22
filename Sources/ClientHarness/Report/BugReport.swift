// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A draft bug report about one failure, complete enough to read and to file.
///
/// The sections follow the bug template of the repository this is destined for, in its order, so that it is pasted rather than rewritten. Every one of them is filled from what the run recorded: there are no blanks to come back to, and no headings standing over nothing.
///
/// That includes the description of the defect, which is not composed but quoted. An expectation in this suite carries a sentence saying what must not happen, written by a person when the test was written, and it describes the defect better than anything assembled afterwards — so writing a good comment beside an expectation is also writing a good bug report.
///
/// What cannot be derived is simply absent. A suspected cause belongs to whoever has read the client's source, and a guess at one in a generated document would send a maintainer down a path for no reason.
///
public struct BugReport: Sendable {
    ///
    /// The failure this is about.
    ///
    public let failure: ReportedFailure

    ///
    /// The room it happened in, if it could be placed in one.
    ///
    public let room: RoomManifest?

    ///
    /// What the run was.
    ///
    public let manifest: RunManifest?

    ///
    /// The lines of the extension's log worth quoting.
    ///
    public let excerpt: [ExtensionLogEntry]

    ///
    /// How many lines of that log were left out.
    ///
    public let omittedLines: Int

    ///
    /// Where the log came from, relative to the run's directory.
    ///
    public let logPath: String?

    ///
    /// Whether the run could say which case of a parameterized test failed.
    ///
    public let hasCaseAttribution: Bool

    ///
    /// Every failure of the run which is this same defect, ``failure`` included.
    ///
    /// Usually more than one. The suite runs every test against every server in the matrix, so a defect in the client shows up once per server — and those are one defect, not four. What they are worth separately is the comparison between them, which is in ``matrixDifferential``.
    ///
    public let occurrences: [ReportedFailure]

    ///
    /// Describe a report.
    ///
    /// - Parameters:
    ///     - failure: The failure it is about.
    ///     - room: The room it happened in.
    ///     - manifest: What the run was.
    ///     - excerpt: The lines of the extension's log worth quoting.
    ///     - omittedLines: How many lines were left out.
    ///     - logPath: Where the log came from.
    ///     - hasCaseAttribution: Whether the failing matrix entry could be established.
    ///     - occurrences: Every failure which is this same defect. Empty means the one.
    ///
    public init(failure: ReportedFailure, room: RoomManifest?, manifest: RunManifest?, excerpt: [ExtensionLogEntry], omittedLines: Int, logPath: String?, hasCaseAttribution: Bool, occurrences: [ReportedFailure] = []) {
        self.excerpt = excerpt
        self.failure = failure
        self.hasCaseAttribution = hasCaseAttribution
        self.logPath = logPath
        self.manifest = manifest
        self.occurrences = occurrences.isEmpty ? [failure] : occurrences
        self.omittedLines = omittedLines
        self.room = room
    }

    ///
    /// Whether the defect appeared on every entry of the matrix the run tested.
    ///
    /// Worth stating on the report itself, because the shape of a failure carries information independent of what the failure says.
    ///
    /// A genuine defect in the client is usually **selective**: it tracks some value of the axis being varied, which is the reason for varying it. A failure which hits every value of an axis at once is, more often than not, a fault in the instrument rather than in the thing being measured — nothing about the client is the same across four server versions except the harness observing it.
    ///
    /// This suite has the worked example. Sixteen failures, uniform across four servers, every one of them produced by a single accessor which returned nothing where it should have returned a value, and none of them by the client. Four successive explanations were written and retracted before the reader itself was suspected. A line saying "uniform across the matrix" would have pointed at the reader on the strength of the shape alone, before anybody read a message.
    ///
    /// It is a prior and not a verdict. A defect present in every supported release is an ordinary thing to find, and this must not become a reason to disbelieve one.
    ///
    public var isUniformAcrossMatrix: Bool {
        guard let differential = matrixDifferential else {
            return false
        }

        return differential.passing.isEmpty && differential.failing.count > 1
    }

    ///
    /// How the entries of the matrix compared, when the run can say.
    ///
    /// The single most informative thing a first report can carry, and the one thing no individual failure knows: that the defect appeared on one version of the server and not on another. A maintainer reading "`latest` failed, `33` passed" has a bisection already started.
    ///
    /// Absent when the run tested one entry, or when it could not attribute failures to entries at all, because a comparison drawn from an incomplete matrix would be a false lead rather than a weak one.
    ///
    public var matrixDifferential: (failing: [String], passing: [String])? {
        guard hasCaseAttribution, let servers = manifest?.servers, servers.count > 1 else {
            return nil
        }

        let all = servers.map(\.description)
        let names = occurrences.compactMap(\.caseDisplayName)

        guard !names.isEmpty else {
            return nil
        }

        let resolved = names.map { Self.server(named: $0, among: all) }

        // Every name the run recorded has to resolve to one of the servers, or the two lists are not describing the same run.
        //
        // Without this, a mismatch — a renamed tag, a manifest from an older schema, a case name the library spelled differently — produces a comparison in which nothing failed and everything passed. The report then states that no server was affected, and withholds the caution about a failure which hit every server, because that caution is derived from the same empty set. Both sentences read as findings.
        guard resolved.allSatisfy({ $0 != nil }) else {
            return nil
        }

        let failing = Set(resolved.compactMap(\.self))
        let passing = all.filter { !failing.contains($0) }

        return (failing: all.filter { failing.contains($0) }, passing: passing)
    }

    ///
    /// Which server a case name names.
    ///
    /// A case display name used to *be* the server, because the tests took one argument. They take two now — the server and the cell — so the name reads `latest, remote metadataUpdate item:dataless kind:file …` and nothing in it equals a server's description any more. The check above compared the two for equality, found no overlap, and returned nothing: the differential has been absent from every report since the day cells became an argument, and the server row of each one has rendered empty. Two derivations of one fact, and only the producer moved.
    ///
    /// Matched longest first, so that `latest` cannot claim a case belonging to `latest+push`.
    ///
    /// - Parameters:
    ///     - name: The case display name, as the testing library wrote it.
    ///     - servers: The servers the run used, as ``RunManifestServer/description`` spells them.
    ///
    /// - Returns: The server, or `nil` if the name does not begin with one.
    ///
    static func server(named name: String, among servers: [String]) -> String? {
        servers
            .sorted { $0.count > $1.count }
            .first { name == $0 || name.hasPrefix("\($0),") }
    }

    ///
    /// What the expectation said about the defect, in the words of whoever wrote the test.
    ///
    /// An expectation in this suite carries a sentence explaining what must not happen, and that sentence is written by a person at the time the test is written. It is the description of the defect, and it is also where the title comes from — which makes writing a good comment beside an expectation the same act as writing a good bug report.
    ///
    /// Source commentary is left out. A line beginning with two slashes is a note to whoever reads the test, not an account of what went wrong.
    ///
    public var summary: String {
        writtenDescription ?? failure.testDisplayName ?? failure.testIdentifier
    }

    ///
    /// The description of the defect as a person wrote it, or nothing.
    ///
    /// Nothing is a real answer here, and the reason this is separate from ``summary``.
    ///
    /// ``summary`` needs some string to make a title out of, so it falls back to the name of the test. As a *title* that is fine. As the **description of a defect** it is a lie in the exact shape of the truth: a test in this suite is named for the property that should hold, so printing that name under a heading asking what went wrong says the opposite of what happened — and says it directly above the *Expected behavior* section, which correctly prints the same sentence.
    ///
    /// The general failure is worth naming because it has now happened twice here in one day, in different sections, from different sources. A renderer with a fallback for every slot always finds something to print, and what it finds is usually true — a good comment, an accurate rationale, the real name of the test. It is simply true about something else. **A renderer that always finds something to print is the hazard; the content it finds is not.**
    ///
    public var writtenDescription: String? {
        // A test which threw never reached an expectation, so there is no sentence beside one to quote — only the error, which is the one thing such a record actually knows.
        if let thrownError = failure.thrownError {
            return thrownError
        }

        let written = failure.comments.filter { !$0.hasPrefix("//") }

        return written.isEmpty ? nil : written.joined(separator: "\n\n")
    }

    ///
    /// Whether the run demonstrated anything about the client.
    ///
    /// A report about a test which threw before it could assert anything is not a bug report, however complete it looks. Saying so on the document is the difference between evidence and an articulate guess.
    ///
    public var isConclusive: Bool {
        failure.isConclusive
    }

    ///
    /// A title for the report.
    ///
    /// The first sentence of ``summary``, because a title is a line and a description is a paragraph.
    ///
    public var title: String {
        guard let sentence = summary.split(separator: ".").first, sentence.count < summary.count else {
            return summary
        }

        return String(sentence) + "."
    }

    ///
    /// A name for the file this is written to.
    ///
    public var slug: String {
        let allowed = CharacterSet.alphanumerics

        let stem = String((failure.testDisplayName ?? failure.testIdentifier).lowercased().unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        })

        return stem.split(separator: "-").prefix(8).joined(separator: "-")
    }
}
