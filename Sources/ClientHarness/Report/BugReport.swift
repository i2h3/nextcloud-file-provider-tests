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
    /// What the expectation said about the defect, in the words of whoever wrote the test.
    ///
    /// An expectation in this suite carries a sentence explaining what must not happen, and that sentence is written by a person at the time the test is written. It is the description of the defect, and it is also where the title comes from — which makes writing a good comment beside an expectation the same act as writing a good bug report.
    ///
    /// Source commentary is left out. A line beginning with two slashes is a note to whoever reads the test, not an account of what went wrong.
    ///
    public var summary: String {
        let written = failure.comments.filter { !$0.hasPrefix("//") }

        guard !written.isEmpty else {
            return failure.testDisplayName ?? failure.testIdentifier
        }

        return written.joined(separator: "\n\n")
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
