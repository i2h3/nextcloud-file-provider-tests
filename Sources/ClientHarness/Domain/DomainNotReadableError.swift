// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A File Provider domain exists but refuses to be read.
///
/// The usual cause is not the provider at all: macOS asks whether this application may access files managed by another one, and a declined or dismissed dialog turns every read of the domain into a refusal. That is worth saying out loud, because the alternative reading — that the client is broken — sends an investigation in entirely the wrong direction.
///
public struct DomainNotReadableError: Error, CustomStringConvertible {
    ///
    /// The domain which could not be read.
    ///
    public let domain: URL

    ///
    /// What the file system said.
    ///
    public let reason: String

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe an unreadable domain in a form which can be read by a human.
    ///
    public var description: String {
        """
        The File Provider domain at \(domain.path(percentEncoded: false)) exists but cannot be read: \(reason)
        macOS asks for that consent once per File Provider domain, and the grant does not outlive the domain: a domain removed and recreated under the same name is asked about again. Since every test builds its own domain, every test needs its dialog answered. If none appeared, macOS suppressed it because it had asked too often in a short time and refused on your behalf.
        """
    }

    ///
    /// Create the error.
    ///
    /// - Parameters:
    ///     - domain: The domain which could not be read.
    ///     - reason: What the file system said.
    ///
    public init(domain: URL, reason: String) {
        self.domain = domain
        self.reason = reason
    }
}
