// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import ServerHarness
import Testing

///
/// Tests for ``ServerTags``.
///
/// The matrix is the current release and the one before it, and the point of deriving it is that nobody has to remember to edit a list when a server release ships. These tests pin the derivation down, because it is the one place where forgetting the policy would go unnoticed: a matrix which quietly tested the wrong pair would still pass.
///
@Suite("Server tags")
struct ServerTagsTests {
    @Test(arguments: [("34.0.3", "33"), ("33.0.11", "32"), ("35.0.0", "34"), ("100.1.2", "99")])
    func `The release before the reported one is its major minus one.`(_ versionString: String, _ expected: String) {
        #expect(ServerTags.previousMajor(before: versionString) == expected)
    }

    ///
    /// This is the case the whole change exists for: the day a 35 is published, the same code tests 35 and 34 without being edited.
    ///
    @Test
    func `A newer release than today's shifts the matrix by itself.`() {
        #expect(ServerTags.previousMajor(before: "34.0.3") == "33")
        #expect(ServerTags.previousMajor(before: "35.0.1") == "34")
    }

    @Test(arguments: ["", "unknown", "v34.0.3"])
    func `A version which cannot be read yields no predecessor rather than a wrong one.`(_ versionString: String) {
        #expect(ServerTags.previousMajor(before: versionString) == nil)
    }

    ///
    /// There is no Nextcloud 0, so a 1 has nothing to pair with. Reporting nothing lets the caller say so plainly instead of trying to deploy a tag which cannot exist.
    ///
    @Test
    func `A first major release has no predecessor.`() {
        #expect(ServerTags.previousMajor(before: "1.0.0") == nil)
    }
}
