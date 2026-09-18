// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Something a cell saw which it deliberately does not assert.
///
/// Some axes describe a choice the system is entitled to make either way. A volume which distinguishes two names differing only by case holds both; one which does not renames the arriving item and records what it renamed it from. Both are correct, so a cell demanding either would fail on a machine formatted differently, and a cell quietly accepting both would pass without saying which it saw — which is how an axis stops measuring anything while still appearing to.
///
/// So the cell records what happened instead of judging it. That only helps if the record outlives the run: an observation which is printed and nothing else exists in a terminal's scrollback, and the thing the encoding axis exists to find out is then gone by the time anybody reads the artifacts.
///
public struct Observation: Codable, Hashable, Sendable {
    ///
    /// The file name suffix marking an attachment which holds an observation.
    ///
    /// The tests write observations as attachments and the runner collects them afterwards, so both sides have to agree on how to recognise one. The same arrangement as ``LatencySample/attachmentSuffix``, and for the same reason: the two targets share nothing but these constants.
    ///
    public static let attachmentSuffix = ".observation.json"

    ///
    /// When it was seen.
    ///
    public let recordedAt: Date

    ///
    /// What was seen, as a sentence.
    ///
    public let text: String

    ///
    /// The clean room it was seen in, which is what ties it back to a cell.
    ///
    public let user: String

    ///
    /// Record an observation.
    ///
    /// - Parameters:
    ///     - text: What was seen.
    ///     - user: The clean room it was seen in.
    ///     - recordedAt: When. Defaults to now.
    ///
    public init(text: String, user: String, recordedAt: Date = Date()) {
        self.recordedAt = recordedAt
        self.text = text
        self.user = user
    }
}
