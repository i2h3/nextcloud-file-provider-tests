// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What `occ status` reports about a Nextcloud installation.
///
/// Only the two fields this suite acts on are modelled. `occ` reports more — the edition, the maintenance flag, whether a database upgrade is pending — and a decoder ignores what it is not asked about, so the rest can be added here the day something needs it.
///
/// Asking for JSON rather than reading the human-readable form is what makes the version usable: the default output is a list of bullet points whose spacing has changed between releases, and a matrix which derives itself from the reported version cannot rest on that.
///
public struct ServerStatus: Codable, Equatable, Sendable {
    ///
    /// Whether Nextcloud has finished installing itself into the container.
    ///
    /// A container answers on its port well before this turns true, so it is the only reliable sign that a server can be used.
    ///
    public let isInstalled: Bool

    ///
    /// The release as a person would write it, such as `34.0.3`.
    ///
    /// This is `versionstring` rather than `version`, which carries a fourth component describing the database schema and is not what anyone means by the release.
    ///
    public let versionString: String

    ///
    /// The major release, such as `34`.
    ///
    /// - Returns: The number, or `nil` if the reported version does not begin with one.
    ///
    public var majorVersion: Int? {
        Int(versionString.prefix { $0.isNumber })
    }

    ///
    /// Decode what `occ status --output=json` printed.
    ///
    /// - Parameters:
    ///     - output: The output of the command.
    ///
    /// - Returns: The decoded status, or `nil` if the output is not a status at all, which is what `occ` produces while the installation is still running.
    ///
    public static func decode(_ output: String) -> ServerStatus? {
        guard let data = output.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ServerStatus.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case isInstalled = "installed"
        case versionString = "versionstring"
    }

    ///
    /// Create a status.
    ///
    /// - Parameters:
    ///     - isInstalled: Whether Nextcloud has finished installing itself.
    ///     - versionString: The release as a person would write it.
    ///
    public init(isInstalled: Bool, versionString: String) {
        self.isInstalled = isInstalled
        self.versionString = versionString
    }
}
