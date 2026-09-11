// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Chooses the handful of log lines worth putting in a report.
///
/// A clean room leaves a few hundred lines behind and a bug report can carry perhaps forty. The choice has to be made without understanding the defect, because nothing here understands it — so the rule leans on what the test already told us: the expectation names the file it was about, and the room names its domain and its user.
///
/// Nothing is dropped silently. Whatever is left out is counted, and the file it came from is named, so that a reader who needs the rest knows it exists.
///
public enum LogExcerpt {
    ///
    /// How long before a failure is worth looking at, by default.
    ///
    /// Asymmetric on purpose: the extension acts and the test then observes the consequence, so what happened afterwards is rarely the cause.
    ///
    public static let lookBehind: TimeInterval = 60

    ///
    /// How long after a failure is worth looking at.
    ///
    public static let lookAhead: TimeInterval = 5

    ///
    /// Words which mark a line as describing a change of state rather than routine progress.
    ///
    /// A heuristic, and named as one wherever it is used. It is deliberately short: a longer list selects everything, which is the same as selecting nothing.
    ///
    public static let notableWords = ["error", "fail", "conflict", "retry", "abort", "cancel", "unauthor", "denied", "timeout", "reject", "block"]

    ///
    /// Pick the lines of a log which are worth quoting about a failure.
    ///
    /// - Parameters:
    ///     - entries: The whole log.
    ///     - failedAt: When the failure happened, if it is known.
    ///     - subjects: Words the failure was about, such as the name of the file under test.
    ///     - limit: How many lines may be quoted.
    ///
    /// - Returns: The chosen lines in the order they were written, and how many were left out.
    ///
    public static func select(from entries: [ExtensionLogEntry], failedAt: Date?, subjects: [String], limit: Int = 40) -> (lines: [ExtensionLogEntry], omitted: Int) {
        guard !entries.isEmpty else {
            return ([], 0)
        }

        var window = entries

        // A window is only worth applying when the failure can be placed in time and the log agrees it was there. A log written in a different zone than the one recorded, or a clock which moved, would otherwise produce an empty excerpt — which reads as "nothing happened" rather than as "this was not found".
        if let failedAt {
            let narrowed = entries.filter { entry in
                guard let date = entry.date else {
                    return false
                }

                return date >= failedAt.addingTimeInterval(-lookBehind) && date <= failedAt.addingTimeInterval(lookAhead)
            }

            if !narrowed.isEmpty {
                window = narrowed
            }
        }

        let collapsed = collapse(window)

        guard collapsed.count > limit else {
            return (collapsed, 0)
        }

        let ranked = collapsed.enumerated().sorted { left, right in
            let leftScore = score(left.element, subjects: subjects)
            let rightScore = score(right.element, subjects: subjects)

            return leftScore == rightScore ? left.offset < right.offset : leftScore > rightScore
        }

        let kept = ranked.prefix(limit).sorted { $0.offset < $1.offset }.map(\.element)

        return (kept, collapsed.count - kept.count)
    }

    ///
    /// How interesting a line is.
    ///
    /// - Parameters:
    ///     - entry: The line.
    ///     - subjects: Words the failure was about.
    ///
    /// - Returns: A score, where more is more interesting.
    ///
    private static func score(_ entry: ExtensionLogEntry, subjects: [String]) -> Int {
        var score = 0

        // The extension's own judgement of what mattered, which costs nothing to take.
        if entry.level != "debug" {
            score += 2
        }

        if entry.reportsError {
            score += 3
        }

        let lowercased = entry.message.lowercased()

        if notableWords.contains(where: { lowercased.contains($0) }) {
            score += 2
        }

        // The strongest signal available, and an entirely mechanical one: the failing expectation named a file, so lines about that file are the ones to keep.
        let described = entry.details.values.joined(separator: " ")

        for subject in subjects where !subject.isEmpty && (described.contains(subject) || entry.message.contains(subject)) {
            score += 4

            break
        }

        return score
    }

    ///
    /// Fold runs of identical lines into one.
    ///
    /// Enumeration is repetitive by nature and can fill an excerpt with the same sentence, which spends the budget without saying anything more.
    ///
    /// - Parameters:
    ///     - entries: The lines.
    ///
    /// - Returns: The lines, with repetition marked rather than repeated.
    ///
    private static func collapse(_ entries: [ExtensionLogEntry]) -> [ExtensionLogEntry] {
        var collapsed = [ExtensionLogEntry]()
        var repeats = 0

        for entry in entries {
            if let previous = collapsed.last, previous.category == entry.category, previous.message == entry.message {
                repeats += 1

                continue
            }

            if repeats > 0, let previous = collapsed.popLast() {
                collapsed.append(mark(previous, repeatedBy: repeats))
                repeats = 0
            }

            collapsed.append(entry)
        }

        if repeats > 0, let previous = collapsed.popLast() {
            collapsed.append(mark(previous, repeatedBy: repeats))
        }

        return collapsed
    }

    ///
    /// Note that a line stood for several identical ones.
    ///
    /// - Parameters:
    ///     - entry: The line.
    ///     - repeats: How many more there were.
    ///
    /// - Returns: The line, saying so.
    ///
    private static func mark(_ entry: ExtensionLogEntry, repeatedBy repeats: Int) -> ExtensionLogEntry {
        ExtensionLogEntry(
            category: entry.category,
            date: entry.date,
            level: entry.level,
            message: "\(entry.message) (× \(repeats + 1))",
            details: entry.details,
            rendered: entry.rendered
        )
    }
}
