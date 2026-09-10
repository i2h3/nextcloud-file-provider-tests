// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One Nextcloud server the test process is expected to run against.
///
/// The ``Runner`` deploys a container per supported server release, then passes the resulting list to the test process as JSON in the `FPT_MATRIX` environment variable, from where ``RunEnvironment`` decodes it. Only servers are described here: users, app passwords, client accounts and File Provider domains are created per test case and therefore cannot be handed in from the outside.
///
public struct ServerUnderTest: Codable, Hashable, Sendable, CustomStringConvertible {
    ///
    /// The password of the server's administrative account, needed to create the per-test users.
    ///
    public let adminPassword: String

    ///
    /// The identifier of the Docker container running this server, as returned by `NextcloudContainerManager`.
    ///
    /// It is the handle for everything which has to happen inside the container, such as `occ` invocations creating a user.
    ///
    public let containerIdentifier: String

    ///
    /// Whether the High Performance Backend for Files is deployed alongside this server.
    ///
    /// The same server release is deployed twice — once with and once without push notifications — to compare propagation behaviour, so this flag is part of a server's identity rather than a global setting.
    ///
    public let isPushEnabled: Bool

    ///
    /// The address the desktop client and ``Rainmaker`` reach this server at.
    ///
    public let serverAddress: URL

    ///
    /// The Docker image tag of the deployed Nextcloud release, for example `33` or `latest`.
    ///
    /// It appears in the description of every parameterized test case as it is reported on the console, which is what makes a matrix run readable while it is happening.
    ///
    public let tag: String

    ///
    /// The release the server reported once it had installed itself, such as `34.0.3`.
    ///
    /// The tag says what was asked for and this says what arrived, which are not the same thing: `latest` is a moving target, and a run recorded weeks apart under the same tag may well have tested two different releases. Optional because a matrix written by an older version of the harness does not carry it.
    ///
    public let versionString: String?

    ///
    /// The user name of the server's administrative account.
    ///
    public let adminUser: String

    ///
    /// A short, stable description used in test names and log lines.
    ///
    public var description: String {
        isPushEnabled ? "\(tag)+push" : tag
    }

    ///
    /// Create a description of a server under test.
    ///
    /// - Parameters:
    ///     - tag: The Docker image tag of the deployed Nextcloud release.
    ///     - serverAddress: The address the desktop client and Rainmaker reach the server at.
    ///     - containerIdentifier: The identifier of the Docker container running the server.
    ///     - adminUser: The user name of the server's administrative account.
    ///     - adminPassword: The password of the server's administrative account.
    ///     - isPushEnabled: Whether the High Performance Backend for Files is deployed alongside the server.
    ///     - versionString: The release the server reported, if it is known.
    ///
    public init(tag: String, serverAddress: URL, containerIdentifier: String, adminUser: String, adminPassword: String, isPushEnabled: Bool, versionString: String? = nil) {
        self.versionString = versionString
        self.adminPassword = adminPassword
        self.adminUser = adminUser
        self.containerIdentifier = containerIdentifier
        self.isPushEnabled = isPushEnabled
        self.serverAddress = serverAddress
        self.tag = tag
    }
}
