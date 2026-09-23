// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``Observation``.
///
/// What a run saw and is not entitled to assert, and what it could not judge at all. Both used to be `print` statements, which made them true of a terminal rather than of a run — and the second is the one a reader most needs, because it is what stands between a green row and the conclusion that everything about that cell was checked.
///
@Suite("Observation")
struct ObservationTests {
    ///
    /// A record written before the type had every field it has now must still read.
    ///
    /// The synthesized decoder refuses one, and every observation on disk from before `isDecline` existed has none — so a report drawn from an older run would have decoded nothing at all, and said nothing about having done so.
    ///
    @Test
    func `An observation written before this type gained its newer fields still decodes.`() throws {
        let json = Data("""
        {"recordedAt": 780000000, "text": "\\"a\\" and \\"A\\" are both held", "user": "remotecreate.file.dataless-0001"}
        """.utf8)

        let observation = try JSONDecoder().decode(Observation.self, from: json)

        #expect(observation.text == "\"a\" and \"A\" are both held")
        #expect(observation.user == "remotecreate.file.dataless-0001")
        #expect(observation.isDecline == false)
    }

    @Test
    func `An observation survives being written and read back.`() throws {
        let observation = Observation(text: "the local version won", user: "conflict.default-0002", recordedAt: Date(timeIntervalSince1970: 1_000_000))
        let decoded = try JSONDecoder().decode(Observation.self, from: JSONEncoder().encode(observation))

        #expect(decoded == observation)
    }

    ///
    /// A decline belongs to the run rather than to a cell, because it is declined for the same reason in every cell which carries that clause.
    ///
    @Test
    func `A decline carries no room and says it is one.`() throws {
        let decline = Observation(text: "noDuplicatesOrOrphans — a POSIX listing cannot show two items of one name", user: nil, isDecline: true)
        let decoded = try JSONDecoder().decode(Observation.self, from: JSONEncoder().encode(decline))

        #expect(decoded.user == nil)
        #expect(decoded.isDecline)
    }
}
