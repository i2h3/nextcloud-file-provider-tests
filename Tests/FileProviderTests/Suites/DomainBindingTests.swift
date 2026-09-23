// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// Tests for how a clean room decides which File Provider domain is its own.
///
/// Hermetic, like ``ScenarioSelectionTests``, and for the same reason: this is a decision made from a directory name, it is made once per room, and getting it wrong sends every read of that room somewhere else while its writes go where they should. A run found exactly that — a room bound to the renamed remnant of its predecessor's domain, and then reported, cell after cell, that items it had just created had never arrived.
///
@Suite("Domain binding")
struct DomainBindingTests {
    ///
    /// The client names a domain directory for the server and then the account, so the account's name ends it.
    ///
    @Test
    func `A domain directory named for the account is recognised as its own.`() {
        let directory = URL(filePath: "/Users/someone/Library/CloudStorage/Nextcloud-127.0.0.1:57240-localmetadataupdate.bundle.dataless-cd2a6289-018", directoryHint: .isDirectory)

        #expect(CleanRoom.isDomain(directory, of: "localmetadataupdate.bundle.dataless-cd2a6289-018"))
    }

    ///
    /// The case this exists for, taken verbatim from the run which found it.
    ///
    /// A domain directory left behind by a previous room is renamed by the system when it is reaped, and the suffix goes on the end — past the account name. The old rule was "the first directory which was not here a moment ago", which a rename satisfies, and which this directory satisfied ahead of the room's own because it sorts earlier.
    ///
    @Test
    func `A remnant renamed by the system is not mistaken for the account's domain.`() {
        let remnant = URL(filePath: "/Users/someone/Library/CloudStorage/Nextcloud-127.0.0.1:57240-localmetadataupdate.bundle.dataless-cd2a6289-017 (23.09.26 15:49)", directoryHint: .isDirectory)

        #expect(!CleanRoom.isDomain(remnant, of: "localmetadataupdate.bundle.dataless-cd2a6289-018"))

        // Nor for the account it once belonged to, which is the more dangerous of the two: that room is over, and a later room for a user of the same name would otherwise inherit its contents.
        #expect(!CleanRoom.isDomain(remnant, of: "localmetadataupdate.bundle.dataless-cd2a6289-017"))
    }

    ///
    /// Another account's domain is not this one's, however similar the names.
    ///
    @Test
    func `A domain of a different account is not recognised.`() {
        let directory = URL(filePath: "/Users/someone/Library/CloudStorage/Nextcloud-127.0.0.1:57240-localdelete.file.dataless-aaaa1111-001", directoryHint: .isDirectory)

        #expect(!CleanRoom.isDomain(directory, of: "localdelete.file.dataless-aaaa1111-002"))

        // A name which merely contains another is not that other. The separator is part of the match for this reason.
        #expect(!CleanRoom.isDomain(directory, of: "dataless-aaaa1111-001"))
    }
}
