// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The failures of a run which are all the same defect seen more than once.
///
/// A run of this suite tests every server in the matrix, so one defect in the client arrives as one failure per server — four identical reports, differing only in a port number and the identifier of the room they happened in. Filing four issues for one defect is worse than filing none, and reading four near-identical documents teaches a reader to skim the fifth.
///
/// So the matrix is treated as what it is: a parameter of one failure rather than four separate defects. What the grouping then makes available is the most informative line a first report can carry — that the defect appeared on one version of the server and not on another, which no single failure can say.
///
public struct FailureGroup: Sendable {
    ///
    /// The failure the report is written about.
    ///
    /// The first one recorded, which is also the one whose room is most likely to still hold its logs.
    ///
    public let representative: ReportedFailure

    ///
    /// Every failure which is this same defect, the representative included.
    ///
    public let occurrences: [ReportedFailure]

    ///
    /// Which entries of the matrix it appeared on.
    ///
    public var matrixEntries: [String] {
        occurrences.compactMap(\.caseDisplayName)
    }

    ///
    /// Collect failures which say the same thing into one group each.
    ///
    /// Grouping is by the test, where in it the expectation stands, and what it said once the parts which differ per run have been taken out of the message. The first two alone would be too coarse: one expectation failing for two genuinely different reasons would be merged and one of the two lost.
    ///
    /// The order of the groups follows the order the failures were recorded, so a report's number reflects when its defect first appeared rather than an ordering nobody asked for.
    ///
    /// - Parameters:
    ///     - failures: The failures of a run.
    ///
    /// - Returns: One group per distinct defect.
    ///
    public static func group(_ failures: [ReportedFailure]) -> [FailureGroup] {
        var order = [String]()
        var collected = [String: [ReportedFailure]]()

        for failure in failures {
            let key = signature(of: failure)

            if collected[key] == nil {
                order.append(key)
                collected[key] = []
            }

            collected[key]?.append(failure)
        }

        return order.compactMap { key in
            guard let occurrences = collected[key], let representative = occurrences.first else {
                return nil
            }

            return FailureGroup(representative: representative, occurrences: occurrences)
        }
    }

    ///
    /// What makes two failures the same defect.
    ///
    /// - Parameters:
    ///     - failure: The failure.
    ///
    /// - Returns: A key which is equal for two failures saying the same thing.
    ///
    public static func signature(of failure: ReportedFailure) -> String {
        let location = failure.sourceLocation?.description ?? "—"

        return "\(failure.testIdentifier)\u{1}\(location)\u{1}\(normalize(failure.message))"
    }

    ///
    /// Take out of a message everything which differs between two runs of the same test.
    ///
    /// Every one of these appears in a real message from this suite. A failed expectation renders the values it was given, and those carry the room's identifier, the port the container happened to be assigned, and the path the item had on this machine — none of which say anything about the defect, and all of which would otherwise make two identical failures look distinct.
    ///
    /// The result is never shown to anybody. It exists only to be compared, so it can be as lossy as it likes.
    ///
    /// - Parameters:
    ///     - message: The message.
    ///
    /// - Returns: The message with the varying parts elided.
    ///
    public static func normalize(_ message: String) -> String {
        var normalized = message

        for pattern in ["file://[^\\s)]+", "/(?:[A-Za-z0-9._~-]+/)+[A-Za-z0-9._~-]*", "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", "[0-9a-fA-F]{8,}", "[0-9]+"] {
            normalized = normalized.replacingOccurrences(of: pattern, with: "\u{2026}", options: .regularExpression)
        }

        return normalized
    }
}
