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

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        switch self {
            case .notUnblocked:
                "The desktop client is still blocked from synchronising. Remove the value by hand with `defaults delete \(ClientPaths.fileProviderExtensionBundleIdentifier) \(ClientSynchronisation.key)`, or every later test will time out."
        }
    }
}
