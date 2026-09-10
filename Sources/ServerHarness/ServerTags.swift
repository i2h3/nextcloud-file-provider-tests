// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Which Nextcloud server releases the suite is run against.
///
/// The matrix is derived rather than written down, because it is not a list of releases but a policy: the current one and the one before it. Naming them here would mean editing this file every time a server release ships, and the edit would be forgotten exactly once before a run started quietly testing the wrong pair.
///
/// So `latest` is deployed first and asked what it is. A server reporting `34.0.3` makes the other half of the matrix `33`, and the day Nextcloud publishes a 35 the same code tests 35 and 34 without being touched. The authority is the running server rather than a registry, which costs one deployment of ordering but needs no second source to be right.
///
public enum ServerTags {
    ///
    /// The tag of the release Nextcloud currently publishes.
    ///
    public static let latest = "latest"

    ///
    /// The tag of the major release before a given one.
    ///
    /// - Parameters:
    ///     - versionString: The version a server reported, such as `34.0.3`.
    ///
    /// - Returns: The tag of the previous major release, such as `33`, or `nil` if the version cannot be read or has no predecessor worth deploying.
    ///
    public static func previousMajor(before versionString: String) -> String? {
        guard let major = ServerStatus(isInstalled: true, versionString: versionString).majorVersion, major > 1 else {
            return nil
        }

        return String(major - 1)
    }
}
