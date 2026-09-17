// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation

///
/// Drafts bug reports from what a run left behind.
///
/// A failed run is normally followed by somebody writing the failure up for the desktop client's issue tracker, and most of that writing is transcription: which client, which server, which macOS, what was asserted, what happened instead. This does the transcription and stops where judgement begins.
///
/// It drafts and never files. Opening an issue is a person's act, and the text of one has to be in their own words.
///
struct Report: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Draft bug reports from the failures of a run."
    )

    ///
    /// The run to report on.
    ///
    @Argument(help: "The run to report on, as a directory or as its identifier. Defaults to the most recent one.")
    var run: String?

    ///
    /// Where runs are collected.
    ///
    @Option(name: .long, help: "The directory runs are collected in.")
    var artifacts: String = "Artifacts"

    ///
    /// How many lines of the extension's log a report may quote.
    ///
    @Option(name: .long, help: "How many lines of the File Provider extension's log a report may quote.")
    var maxLogLines: Int = 40

    ///
    /// Whether a report which already exists may be replaced.
    ///
    @Flag(name: .long, help: "Replace reports which already exist. Without this they are left alone, because a draft is meant to be finished by hand.")
    var force = false

    ///
    /// Draft the reports.
    ///
    /// - Throws: ``ReportError`` if the run cannot be found, or whatever writing raises.
    ///
    func run() async throws {
        let artifactsDirectory = URL(filePath: artifacts, directoryHint: .isDirectory)
        let directory = try resolveRun(in: artifactsDirectory)
        let evidence = RunEvidence.gather(from: directory)

        // Rebuilt every time, which is what makes a run recorded before this existed readable now. It describes what the run did rather than what went wrong, so it is written whether or not anything did.
        Console.log("Overview:  \(try RunIndex.write(for: evidence).path(percentEncoded: false))")

        guard !evidence.failures.isEmpty else {
            Console.log("The run at \(directory.lastPathComponent) had no failures. Nothing further to report.")

            return
        }

        let written = try BugReportWriter.write(for: evidence, isOverwriting: force)

        guard !written.isEmpty else {
            Console.log("Every failure of \(directory.lastPathComponent) is either already known or already drafted. Use --force to write the drafts again.")

            return
        }

        Console.log("Drafted \(written.all.count) document\(written.all.count == 1 ? "" : "s") from \(directory.lastPathComponent):")
        Console.describe(written)

        // Only where there is something to file. Saying it over a list of measurements which never happened is how one of them ends up in somebody's issue tracker.
        if !written.conclusive.isEmpty {
            Console.log()
            Console.log("Each is a draft of what the run found. Read one before filing it, and file it yourself.")
        }
    }

    ///
    /// Work out which run was meant.
    ///
    /// - Parameters:
    ///     - artifactsDirectory: The directory runs are collected in.
    ///
    /// - Returns: The run's directory.
    ///
    /// - Throws: ``ReportError`` if there is none.
    ///
    private func resolveRun(in artifactsDirectory: URL) throws -> URL {
        guard let run else {
            guard let recent = RunEvidence.mostRecentRun(in: artifactsDirectory) else {
                throw ReportError.noRunFound(directory: artifactsDirectory.path(percentEncoded: false))
            }

            return recent
        }

        // A run may be named by its identifier, which is how it appears in the output of the run itself, or by a path for anything unusual.
        let named = artifactsDirectory.appending(path: run, directoryHint: .isDirectory)

        if try LocalDirectory.exists(named) {
            return named
        }

        let given = URL(filePath: run, directoryHint: .isDirectory)

        guard try LocalDirectory.exists(given) else {
            throw ReportError.runNotFound(name: run)
        }

        return given
    }
}
