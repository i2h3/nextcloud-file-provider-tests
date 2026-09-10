// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import ServerHarness
import Testing

///
/// Tests for ``TestUserName``.
///
/// The derived name is what connects a leftover user or directory on a server back to the test which created it, and it doubles as the account password. Both properties are easy to break by accident, so they are pinned down here rather than discovered against a live server.
///
@Suite("Test user names")
struct TestUserNameTests {
    @Test
    func `A name is derived from the test and stays recognisable.`() {
        let derived = TestUserName.derive(from: "DomainLifecycle.startsEmpty", ordinal: 1)

        #expect(derived.hasPrefix("domainlifecycle.startsempty-"))
    }

    @Test
    func `A name is the same in every process and every run.`() {
        #expect(TestUserName.derive(from: "Suite.test", ordinal: 7) == TestUserName.derive(from: "Suite.test", ordinal: 7))
    }

    @Test
    func `Different tests get different names.`() {
        #expect(TestUserName.derive(from: "Suite.one", ordinal: 1) != TestUserName.derive(from: "Suite.two", ordinal: 1))
    }

    ///
    /// This is what a parameterized test relies on. Its runs share a test name, so without the ordinal they would share a user, and through the user a File Provider domain directory, which is the one thing the machine cannot hold two of.
    ///
    @Test
    func `Repeated runs of one test get different names.`() {
        let names = (1 ... 25).map { TestUserName.derive(from: "Naming.fromServer", ordinal: $0) }

        #expect(Set(names).count == names.count)
    }

    @Test(arguments: ["Suite.test", "Weird Name/With:Punctuation!", "Ümlaut.tëst", "a"])
    func `Only characters the server accepts are used.`(_ testName: String) {
        let derived = TestUserName.derive(from: testName, ordinal: 3)

        #expect(derived.unicodeScalars.allSatisfy { TestUserName.allowedCharacters.contains($0) })
    }

    @Test(arguments: ["a", "Suite.test", String(repeating: "long", count: 40)], [1, 999])
    func `A name is long enough to be accepted as a password and short enough to be accepted as a name.`(_ testName: String, _ ordinal: Int) {
        let derived = TestUserName.derive(from: testName, ordinal: ordinal)

        #expect(derived.count >= TestUserName.minimumLength)
        #expect(derived.count <= TestUserName.maximumLength)
    }
}
