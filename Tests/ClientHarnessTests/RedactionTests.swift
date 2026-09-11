// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``Redaction``.
///
/// Everything a draft report quotes was written by a program which had no idea it would be published. This is the last thing standing between that and a public issue tracker, so it is tested for what it removes and — just as much — for what it must not remove, because a report which has had its evidence scrubbed away is no longer evidence.
///
@Suite("Redaction")
struct RedactionTests {
    @Test
    func `A home directory loses the name of whoever owns it.`() {
        let redacted = Redaction.apply(to: "at /Users/someone/Library/CloudStorage/Nextcloud-localhost")

        #expect(!redacted.contains("someone"))
        #expect(redacted.contains("~/Library/CloudStorage"))
    }

    ///
    /// Not only safe but better: what is left is the path a maintainer can open in their own checkout.
    ///
    @Test
    func `A path inside a checkout of the client becomes one anybody can follow.`() {
        let redacted = Redaction.apply(to: "[ warning ] /Users/iva/Desktop/Client/src/gui/application.cpp:956 something happened")

        #expect(redacted.contains("src/gui/application.cpp:956"))
        #expect(!redacted.contains("/Users/"))
        #expect(!redacted.contains("Desktop/Client"))
    }

    @Test
    func `A named secret is taken out wherever it appears.`() {
        let redacted = Redaction.apply(to: "password=swordfish and again swordfish", secrets: ["swordfish"])

        #expect(!redacted.contains("swordfish"))
    }

    ///
    /// A report is made of what the run observed, and most of that is harmless. Over-redaction costs a reader the thread back to the evidence, which is the one thing a report cannot do without.
    ///
    @Test
    func `What is harmless is left alone.`() {
        let text = "server http://localhost:53406 held contested.bin for user conflict.simultaneousmodification-ee2ce462-001"

        #expect(Redaction.apply(to: text) == text)
    }

    @Test
    func `The application the client is installed as is not a home directory.`() {
        let redacted = Redaction.apply(to: "34.0.50 at /Applications/Nextcloud.app/")

        #expect(redacted.contains("/Applications/Nextcloud.app/"))
    }

    ///
    /// Used to refuse rather than to repair: a report which cannot be made safe should say so instead of going out half-scrubbed.
    ///
    @Test
    func `Anything still carrying a home directory or a secret is recognised as unsafe.`() {
        #expect(Redaction.containsSecrets("/Users/someone/thing", secrets: []))
        #expect(Redaction.containsSecrets("the password is swordfish", secrets: ["swordfish"]))
        #expect(!Redaction.containsSecrets("~/thing and localhost", secrets: ["swordfish"]))
    }

    @Test
    func `An empty secret does not match everything.`() {
        #expect(Redaction.apply(to: "unchanged", secrets: [""]) == "unchanged")
        #expect(!Redaction.containsSecrets("unchanged", secrets: [""]))
    }
}
