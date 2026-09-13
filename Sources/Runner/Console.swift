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
