// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``EnumerationLedger``.
///
@Suite("Enumeration ledger")
struct EnumerationLedgerTests {
    @Test
    func `A ledger starts empty and knows nothing was enumerated.`() {
        let ledger = EnumerationLedger()

        #expect(ledger.entries.isEmpty)
        #expect(!ledger.hasEnumerated(URL(filePath: "/domain")))
    }

    @Test
    func `Recorded enumerations are kept in order.`() {
        let ledger = EnumerationLedger()
        ledger.record(URL(filePath: "/domain"), entryCount: 2)
        ledger.record(URL(filePath: "/domain/folder"), entryCount: 0)

        #expect(ledger.entries.map(\.directory.lastPathComponent) == ["domain", "folder"])
        #expect(ledger.entries.first?.entryCount == 2)
    }

    @Test
    func `A directory is recognised regardless of how its path is spelled.`() {
        let ledger = EnumerationLedger()
        ledger.record(URL(filePath: "/domain/folder/"), entryCount: 1)

        #expect(ledger.hasEnumerated(URL(filePath: "/domain/folder")))
        #expect(!ledger.hasEnumerated(URL(filePath: "/domain/other")))
    }
}
