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
    /// The clean room it was seen in, which is what ties it back to a cell, or `nil` where it belongs to the run rather than to one cell.
    ///
    /// A decline is the case with no room. It says a clause could not be judged, and it is declined for the same reason in every cell which carries that clause, so recording it per cell would bury a run in one identical paragraph per case — which is not merely noisy: it teaches a reader to skim exactly the part saying what is not covered.
    ///
    public let user: String?

    ///
    /// Whether this says a clause could not be judged, rather than which of several permitted results happened.
    ///
    /// Two different statements, kept apart because a reader has to tell them apart. An observation is evidence: the client did one of the legal things and here is which. A decline is an absence of evidence: nothing was measured here, and a cell which passed did so without this clause being checked. Rendering them alike would let the second read as the first.
    ///
    public let isDecline: Bool

    ///
    /// Record an observation.
    ///
    /// - Parameters:
    ///     - text: What was seen.
    ///     - user: The clean room it was seen in, or `nil` for the run as a whole.
    ///     - isDecline: Whether this says a clause could not be judged. Defaults to `false`.
    ///     - recordedAt: When. Defaults to now.
    ///
    public init(text: String, user: String?, isDecline: Bool = false, recordedAt: Date = Date()) {
        self.isDecline = isDecline
        self.recordedAt = recordedAt
        self.text = text
        self.user = user
    }

    // MARK: - Decodable

    ///
    /// Read an observation, including one written before this type had every field it has now.
    ///
    /// Written by hand rather than synthesized, because the synthesized version refuses a record with no `isDecline` — and every observation on disk from before that field existed has none. A report drawn from an older run would then have decoded nothing and said nothing, silently, which is the failure this whole type was added to prevent.
    ///
    /// - Parameters:
    ///     - decoder: The decoder to read from.
    ///
    /// - Throws: Whatever decoding the fields which have always been required raises.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isDecline = try container.decodeIfPresent(Bool.self, forKey: .isDecline) ?? false
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        text = try container.decode(String.self, forKey: .text)
        user = try container.decodeIfPresent(String.self, forKey: .user)
    }
}
