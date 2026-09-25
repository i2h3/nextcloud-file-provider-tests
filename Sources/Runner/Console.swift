// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation

///
/// Writes progress to the terminal, immediately.
///
/// A run deploys containers and waits for domains for minutes at a time. Standard output is block buffered whenever it is not a terminal — which is the case in continuous integration and whenever the output is piped — so without an explicit flush the whole run would appear to hang and then print everything at once. Every line the runner emits therefore goes through here.
///
enum Console {
    ///
    /// Write a line and flush it.
    ///
    /// - Parameters:
    ///     - message: The line to write.
    ///
    static func log(_ message: String = "") {
        print(message)
        fflush(stdout)
    }

    ///
    /// Write a line stamped with the time of day.
    ///
    /// For the milestones of a run and nothing else: when it began, when the servers were up, when the tests started and stopped, when it was over. A run takes hours, the terminal keeps the output of the last several, and without these a scrollback gives no way to tell which run is on the screen or whether the thing still has work to do — which is the question somebody actually has when they come back to it.
    ///
    /// Local time, because the reader is sitting in it. The artifacts keep the same moments in UTC with a zone beside them, so nothing here has to be the record.
    ///
    /// - Parameters:
    ///     - message: The line to write.
    ///
    static func milestone(_ message: String) {
        log("[\(timestamp())] \(message)")
    }

    ///
    /// The time of day, to the second.
    ///
    /// - Parameters:
    ///     - moment: When. Defaults to now.
    ///
    /// - Returns: The text.
    ///
    static func timestamp(_ moment: Date = Date()) -> String {
        moment.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    ///
    /// Say how long something took, the way a person would.
    ///
    /// - Parameters:
    ///     - interval: How long, in seconds.
    ///
    /// - Returns: The text.
    ///
    static func spoken(_ interval: TimeInterval) -> String {
        let whole = Int(interval.rounded())
        let parts = [(whole / 3600, "hour"), (whole % 3600 / 60, "minute"), (whole % 60, "second")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }

        guard let last = parts.last else {
            return "less than a second"
        }

        guard parts.count > 1 else {
            return last
        }

        return "\(parts.dropLast().joined(separator: ", ")) and \(last)"
    }

    ///
    /// Announce what drafting a run produced, keeping the two kinds apart.
    ///
    /// They are printed separately because they ask different things of whoever reads them. A draft about a contradicted expectation is on its way to the client's issue tracker. A record of a measurement which never happened is on its way back to this suite, and putting the two under one heading invites somebody to file the second.
    ///
    /// - Parameters:
    ///     - reports: What was drafted.
    ///
    static func describe(_ reports: DraftedReports) {
        if !reports.conclusive.isEmpty {
            log("Drafted \(reports.conclusive.count) bug report\(reports.conclusive.count == 1 ? "" : "s"), to be finished by hand and filed by you:")

            for url in reports.conclusive {
                log("  \(url.path(percentEncoded: false))")
            }
        }

        if !reports.inconclusive.isEmpty {
            if !reports.conclusive.isEmpty {
                log()
            }

            log("\(reports.inconclusive.count) test\(reports.inconclusive.count == 1 ? "" : "s") raised an error before reaching an expectation, so \(reports.inconclusive.count == 1 ? "that measurement was" : "those measurements were") not made. These are not bug reports — read them before treating anything in them as a finding about the client:")

            for url in reports.inconclusive {
                log("  \(url.path(percentEncoded: false))")
            }
        }
    }

    ///
    /// Write a question and flush it, leaving the cursor on the same line.
    ///
    /// - Parameters:
    ///     - message: The question to write.
    ///
    static func ask(_ message: String) {
        print(message, terminator: "")
        fflush(stdout)
    }
}
