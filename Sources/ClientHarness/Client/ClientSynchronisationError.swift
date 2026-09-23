// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A problem blocking or unblocking the desktop client's synchronisation.
///
public enum ClientSynchronisationError: Error, Equatable, CustomStringConvertible {
    ///
    /// The client is still blocked from synchronising after being told not to be.
    ///
    /// This is worth raising loudly rather than passing over. A machine left blocked looks like a machine on which every later test simply times out, with nothing to say why.
    ///
    case notUnblocked

    ///
    /// Whether the client is blocked could not be read at all.
    ///
    /// Distinct from ``notUnblocked`` because the machine is in an unknown state rather than a known bad one, and because the fix is different: this one is a grant, not a stray value. It used to be indistinguishable from success — a read which could not happen counted as the switch being absent, so unblocking confirmed itself by failing to look.
    ///
    case blockStateUnreadable(String)

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        switch self {
            case .notUnblocked:
                "The desktop client is still blocked from synchronising. Remove the value by hand with `defaults delete \(ClientPaths.fileProviderExtensionBundleIdentifier) \(ClientSynchronisation.key)`, or every later test will time out."

            case let .blockStateUnreadable(detail):
                "Whether the desktop client is blocked from synchronising could not be read, so unblocking it could not be confirmed, and it was retried for \(ClientSynchronisation.confirmationWindow) before giving up. \(detail). If that reads as a refusal rather than an absence, this machine is missing the grant macOS 27 requires for the client's application data, and every later test would have timed out with nothing to say why."
        }
    }
}
