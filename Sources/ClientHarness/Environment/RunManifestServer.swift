// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One server of a run, as it is safe to write down.
///
/// This exists rather than recording ``ServerUnderTest`` because that type carries the administrative account's name and password. It is written to a file which feeds a document destined for a public issue tracker, so it describes the server and nothing else. Credentials belong in the environment of a running process, not in an artifact.
///
public struct RunManifestServer: Codable, Equatable, Sendable {
    ///
    /// The Docker image tag the server was asked for, such as `33` or `latest`.
    ///
    public let tag: String

    ///
    /// The release the server reported once it had installed itself, such as `34.0.3`.
    ///
    /// The distinction from ``tag`` is the reason this is recorded at all: `latest` is a moving target, and two runs weeks apart under the same tag may have tested different releases. A bug report has to name the release which was actually running.
    ///
    public let versionString: String?

    ///
    /// Whether the High Performance Backend for Files was deployed alongside it.
    ///
    public let isPushEnabled: Bool

    ///
    /// The address the client and the tests reached it at.
    ///
    /// Kept because it is a local address which says nothing anyone could use, and because it is how a log line is matched to a server.
    ///
    public let serverAddress: URL

    ///
    /// The identifier of the container it ran in.
    ///
    public let containerIdentifier: String

    ///
    /// A short description, the way a test case names it.
    ///
    public var description: String {
        isPushEnabled ? "\(tag)+push" : tag
    }

    ///
    /// Describe a server of a run.
    ///
    /// - Parameters:
    ///     - server: The server to describe, whose credentials are deliberately left behind.
    ///
    public init(_ server: ServerUnderTest) {
        containerIdentifier = server.containerIdentifier
        isPushEnabled = server.isPushEnabled
        serverAddress = server.serverAddress
        tag = server.tag
        versionString = server.versionString
    }
}
