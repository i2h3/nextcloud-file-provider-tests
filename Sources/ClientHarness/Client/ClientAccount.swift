// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The credentials of one Nextcloud account for the desktop client to be configured with.
///
/// A clean room creates exactly one of these per test case, from a user which exists only for that test, and hands it to ``DesktopClient/launch(configuration:)`` as command line options. Passing the account this way is what makes the setup headless: the client's account wizard and its browser login flow are never involved.
///
public struct ClientAccount: Hashable, Sendable {
    ///
    /// The app password issued by the server for this account.
    ///
    public let appPassword: String

    ///
    /// The address of the server the account lives on.
    ///
    public let serverAddress: URL

    ///
    /// The user name on the server, as `occ user:add` created it.
    ///
    public let userIdentifier: String

    ///
    /// Create an account description.
    ///
    /// - Parameters:
    ///     - serverAddress: The address of the server the account lives on.
    ///     - userIdentifier: The user name on the server.
    ///     - appPassword: The app password issued by the server.
    ///
    public init(serverAddress: URL, userIdentifier: String, appPassword: String) {
        self.appPassword = appPassword
        self.serverAddress = serverAddress
        self.userIdentifier = userIdentifier
    }
}
