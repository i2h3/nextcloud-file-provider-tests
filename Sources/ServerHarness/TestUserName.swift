// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Derives the Nextcloud user name a test case runs as.
///
/// Every test gets its own user, so the user's files root is the test's workspace and no cleanup can leak into another test. The name is derived from the test rather than generated, because a stray user or a leftover directory on a server should say which test left it behind.
///
/// A test which is parameterized runs its body several times, and each of those runs needs a user of its own: they share a test name, and a shared name would mean a shared File Provider domain directory, which is the one piece of per-test state the machine cannot hold twice. The ordinal is what separates them, so the name says both which test it belongs to and which of its runs.
///
public enum TestUserName {
    ///
    /// The characters `occ user:add` accepts in a user name.
    ///
    public static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.@")

    ///
    /// The longest a derived name may become before it is shortened.
    ///
    public static let maximumLength = 48

    ///
    /// The shortest a derived name may be.
    ///
    /// Nextcloud rejects short passwords, and ``TestUser`` uses the name as the account password, so a very short test name would otherwise fail at user creation rather than in the test.
    ///
    public static let minimumLength = 16

    ///
    /// Derive the user name for a test.
    ///
    /// - Parameters:
    ///     - testName: The test the user belongs to, conventionally `<suite>.<test>`.
    ///     - ordinal: Which run of that test this is, counted within the process.
    ///
    /// - Returns: A name which is acceptable to the server, recognisable, and unique for this run.
    ///
    public static func derive(from testName: String, ordinal: Int) -> String {
        let lowercased = testName.lowercased()

        let sanitized = String(lowercased.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        })

        let suffix = String(format: "%08x-%03d", stableHash(of: testName), ordinal)
        let room = maximumLength - suffix.count - 1
        let stem = sanitized.count > room ? String(sanitized.prefix(room)) : sanitized
        let derived = "\(stem)-\(suffix)"

        guard derived.count < minimumLength else {
            return derived
        }

        return derived.padding(toLength: minimumLength, withPad: "0", startingAt: 0)
    }

    ///
    /// A hash which is the same in every process and every run.
    ///
    /// Swift's own hashing is seeded per process, so it cannot be used here: a user name has to be reproducible for a test which is investigated a day later.
    ///
    /// - Parameters:
    ///     - value: The value to hash.
    ///
    /// - Returns: The hash.
    ///
    public static func stableHash(of value: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261

        for byte in Data(value.utf8) {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }

        return hash
    }
}
