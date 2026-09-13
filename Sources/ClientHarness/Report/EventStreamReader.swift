// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads what the test process recorded about its own run.
///
/// The testing library will write every event of a run as JSON, one object per line, if it is asked. It is the only artifact which says which case of a parameterized test failed — the xUnit report collapses them all into one entry — and the only one which timestamps a failure, which is what connects it to the clean room it happened in.
///
/// The option which produces it is undocumented, so nothing here assumes the file exists or that its shape is what it was. Every field is read defensively and a line which cannot be understood is skipped rather than thrown, because a report which is missing a detail is worth more than a report which refused to be written.
///
public enum EventStreamReader {
    ///
    /// The name of the file a run records its events in.
    ///
    public static let fileName = "events.jsonl"

    ///
    /// Read the failures a run recorded.
    ///
    /// - Parameters:
    ///     - url: The file to read.
    ///
    /// - Returns: The failures, in the order they happened, or an empty array if the file cannot be read at all.
    ///
    public static func failures(in url: URL) -> [ReportedFailure] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var displayNames = [String: String]()
        var failures = [ReportedFailure]()

        for line in contents.split(separator: "\n") {
            guard let data = line.data(using: .utf8), let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = record["payload"] as? [String: Any] else {
                continue
            }

            // The library announces every test before running it, which is where the names a person reads come from. Events themselves carry only identifiers.
            if record["kind"] as? String == "test", let identifier = payload["id"] as? String {
                displayNames[identifier] = payload["displayName"] as? String ?? payload["name"] as? String
            }

            guard payload["kind"] as? String == "issueRecorded", let identifier = payload["testID"] as? String else {
                continue
            }

            failures.append(makeFailure(payload: payload, identifier: identifier, displayNames: displayNames))
        }

        return failures
    }

    ///
    /// Turn one recorded issue into a failure.
    ///
    /// - Parameters:
    ///     - payload: The issue as the library wrote it.
    ///     - identifier: The identifier of the test which failed.
    ///     - displayNames: The names announced so far, keyed by identifier.
    ///
    /// - Returns: The failure.
    ///
    private static func makeFailure(payload: [String: Any], identifier: String, displayNames: [String: String]) -> ReportedFailure {
        let messages = payload["messages"] as? [[String: Any]] ?? []

        // The library separates what failed from what was said about it: one message carries the expectation, the rest are whatever comment stood beside it.
        let message = messages.first { $0["symbol"] as? String == "fail" }?["text"] as? String
        let comments = messages.filter { $0["symbol"] as? String != "fail" }.compactMap { $0["text"] as? String }

        let issue = payload["issue"] as? [String: Any] ?? [:]
        var location: ReportedSourceLocation?

        // Only the file identifier is taken. The absolute path beside it is somebody's home directory.
        if let raw = payload["_sourceLocation"] as? [String: Any] ?? issue["sourceLocation"] as? [String: Any], let fileIdentifier = raw["fileID"] as? String, let line = raw["line"] as? Int {
            location = ReportedSourceLocation(fileIdentifier: fileIdentifier, line: line)
        }

        var occurredAt: Date?

        if let instant = payload["instant"] as? [String: Any], let since1970 = instant["since1970"] as? Double {
            occurredAt = Date(timeIntervalSince1970: since1970)
        }

        return ReportedFailure(
            testIdentifier: identifier,
            testDisplayName: displayNames[identifier],
            // Deliberately the display name and never the identifier beside it: the library builds that identifier by encoding the argument, and this suite's argument once carried a password.
            caseDisplayName: (payload["_testCase"] as? [String: Any])?["displayName"] as? String,
            message: message ?? comments.first ?? "A failure was recorded without a message.",
            comments: comments,
            sourceLocation: location,
            occurredAt: occurredAt,
            isKnown: issue["isKnown"] as? Bool ?? false,
            // Present only when the test threw. Its absence is what says an expectation was contradicted rather than a step abandoned, and the two mean opposite things about who has a problem.
            thrownError: (issue["_error"] as? [String: Any]).map { error in
                let domain = error["domain"] as? String ?? "an unnamed domain"

                return (error["description"] as? String).map { "\($0) (\(domain))" } ?? domain
            }
        )
    }
}
