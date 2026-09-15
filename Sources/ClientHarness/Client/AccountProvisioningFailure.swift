// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The client was asked to configure an account and did not.
///
/// Raised where it happens rather than where it is noticed. Without it the run continues into the launch which is supposed to turn the account into a File Provider domain, waits the full two minutes for a domain nothing has requested, and reports that no domain appeared — which sends the reader to the File Provider, to the extension, and to macOS, none of which were ever involved.
///
public struct AccountProvisioningFailure: Error, CustomStringConvertible {
    ///
    /// The account which was asked for.
    ///
    public let account: ClientAccount

    ///
    /// The accounts the client's configuration holds instead.
    ///
    public let configured: [String]

    ///
    /// Describe an account the client did not configure.
    ///
    /// - Parameters:
    ///     - account: The account which was asked for.
    ///     - configured: The accounts the client's configuration holds instead.
    ///
    public init(account: ClientAccount, configured: [String]) {
        self.account = account
        self.configured = configured
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        let found = configured.isEmpty ? "none at all" : configured.joined(separator: ", ")

        return "The client was asked to configure \(account.userIdentifier) at \(account.serverAddress.absoluteString) and its configuration afterwards holds \(found). Its own log says what it was doing when it stopped; the request it makes first is to /ocs/v1.php/cloud/user."
    }
}
