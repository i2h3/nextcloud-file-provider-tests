// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Takes out of a report the things which should not leave the machine which produced it.
///
/// A bug report drafted here is meant to be pasted into a public issue tracker, and everything it quotes was written by a program which had no idea that was going to happen. The client's own log carries the absolute path of the machine it was built on; the testing library carries the absolute path of the file it was running; a test user's name is also its password.
///
/// The rewrites are not only removals. A client log line reading `/Users/someone/Desktop/Client/src/gui/application.cpp:956` becomes `src/gui/application.cpp:956`, which is both safe and better: it is the path a maintainer can actually open.
///
public enum Redaction {
    ///
    /// Rewrite a string so that it can be published.
    ///
    /// - Parameters:
    ///     - text: The text to rewrite.
    ///     - secrets: Values which must not appear whatever they look like, such as the passwords of the run's users.
    ///
    /// - Returns: The rewritten text.
    ///
    public static func apply(to text: String, secrets: [String] = []) -> String {
        var redacted = text

        // A path inside a checkout of the client is worth keeping, but only the part which exists in the repository everyone shares.
        redacted = redacted.replacingOccurrences(of: #"/[^\s:'"]*/src/"#, with: "src/", options: .regularExpression)

        // Everything else rooted in somebody's home directory keeps its shape without naming them.
        redacted = redacted.replacingOccurrences(of: #"/Users/[^/\s:'"]+"#, with: "~", options: .regularExpression)

        for secret in secrets where !secret.isEmpty {
            redacted = redacted.replacingOccurrences(of: secret, with: "«redacted»")
        }

        return redacted
    }

    ///
    /// Whether a string still holds anything which must not be published.
    ///
    /// Used to fail loudly rather than to fix quietly: a report which cannot be made safe should say so instead of going out half-scrubbed.
    ///
    /// - Parameters:
    ///     - text: The text to inspect.
    ///     - secrets: The values which must not appear.
    ///
    /// - Returns: `true` if anything was found.
    ///
    public static func containsSecrets(_ text: String, secrets: [String]) -> Bool {
        for secret in secrets where !secret.isEmpty && text.contains(secret) {
            return true
        }

        return text.contains("/Users/")
    }
}
