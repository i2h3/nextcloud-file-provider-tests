// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads what the desktop client wrote about itself.
///
/// The client keeps rotated, sometimes compressed log files in ``ClientPaths/logDirectory``. Only the current one is read here, and only to answer one question: has the client already reported that it cannot do what a test is waiting for?
///
/// That question matters because the alternative is waiting for a timeout. A client which refuses to configure an account says so within a second; without reading the log, the test would spend two minutes waiting for a domain that was never going to appear, and would then report a timeout instead of the reason.
///
public enum ClientLog {
    ///
    /// The lines which mean that the client has given up on setting up an account.
    ///
    /// Each of these was observed on client 34.0.3. They are matched as substrings, so that the surrounding formatting and the account name do not matter.
    ///
    public static let accountSetupFailureSignatures = [
        "Refusing to add classic sync folder: File Provider mode is enabled.",
        "setup from command line failed",
        "Could not create local folder because the name is empty",
    ]

    ///
    /// The current log file, if the client has written one.
    ///
    /// - Returns: The most recently modified uncompressed log file.
    ///
    public static func currentLogFile() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ClientPaths.logDirectory.path(percentEncoded: false))) ?? []

        let candidates = names
            .filter { $0.contains("nextcloud.log") && !$0.hasSuffix(".gz") }
            .map { ClientPaths.logDirectory.appending(path: $0, directoryHint: .notDirectory) }

        // A candidate whose date cannot be read is dropped rather than ranked as the oldest. Ranking it oldest meant an unreadable current log lost to a rotated one, and "the newest log" then named a file from a previous run.
        let dated = candidates.compactMap { url -> (URL, Date)? in
            guard let date = (try? LocalNode.at(url))??.modificationDate else {
                return nil
            }

            return (url, date)
        }

        return dated.max { $0.1 < $1.1 }?.0
    }

    ///
    /// The first line of the current log which matches one of the given signatures.
    ///
    /// - Parameters:
    ///     - signatures: The substrings to look for.
    ///
    /// - Returns: The whole matching line, trimmed, or `nil` if none matches.
    ///
    public static func firstLine(matching signatures: [String]) -> String? {
        guard let url = currentLogFile() else {
            return nil
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(separator: "\n") where signatures.contains(where: { line.contains($0) }) {
            return line.trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    ///
    /// Whether the client has reported that it could not set up the account.
    ///
    /// - Returns: The line saying so, or `nil` if it has not.
    ///
    public static func accountSetupFailure() -> String? {
        firstLine(matching: accountSetupFailureSignatures)
    }
}
