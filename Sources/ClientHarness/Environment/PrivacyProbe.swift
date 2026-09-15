// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A location whose readability answers whether this process holds a privacy grant.
///
/// Asking the question directly is not possible: there is no supported way for a process to enumerate its own privacy grants. What it can do is read something only a holder of the grant may read and see what the refusal looks like, which is why every probe here names a file rather than a permission.
///
/// The probe reports through ``PrivacyProbeOutcome`` rather than a `Bool`, because `FileManager.isReadableFile(atPath:)` — which this used to be written on — returns `false` both for a refusal and for a path which is not there. macOS 27 turned that conflation into a false failure: it moved the per-user privacy database into `/private/var/containers/Data/ProtectedSystem`, the probe's old path stopped existing, and the suite told a machine with Full Disk Access that it had none.
///
public struct PrivacyProbe: Sendable {
    ///
    /// The locations which only Full Disk Access opens.
    ///
    /// More than one, because a probe expires when the operating system moves what it points at, and a single expired probe is indistinguishable from a refusal. The per-user privacy database is deliberately absent from this list: since macOS 27 it lives inside a protected container which Full Disk Access does not open either, so it can no longer answer this question for any macOS.
    ///
    public static let fullDiskAccess = [
        PrivacyProbe(url: URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db", directoryHint: .notDirectory), subject: "the system privacy database"),
        PrivacyProbe(url: ClientPaths.home.appending(path: "Library/Safari/Bookmarks.plist", directoryHint: .notDirectory), subject: "Safari's bookmarks"),
    ]

    ///
    /// The locations holding the state of the client under test.
    ///
    /// Separate from ``fullDiskAccess`` because since macOS 27 they are separately protected. `/usr/libexec/sandboxd` carries a hardcoded list of applications whose data is guarded by `kTCCServiceSystemPolicyAppDataDetailed`, and both `com.nextcloud.desktopclient` and the group container `NKUJUXUJ3B/com.nextcloud.desktopclient` are named in it. Measured on macOS 27.0: Full Disk Access satisfies that service too, so this asks nothing extra of anybody. It is asked separately because it was not known to be the same grant, and because a refusal here is indistinguishable from a client which has never run.
    ///
    /// These are the files the suite draws its evidence from, not stand-ins: the configuration the accounts live in, and the directory the File Provider extension writes one log per domain into.
    ///
    public static let clientApplicationData = [
        PrivacyProbe(url: ClientPaths.configurationFile, subject: "the client's configuration"),
        PrivacyProbe(url: ClientPaths.extensionLogs, subject: "the extension's logs"),
    ]

    ///
    /// What is being read, phrased to be read inside a sentence.
    ///
    public let subject: String

    ///
    /// The location to read.
    ///
    public let url: URL

    ///
    /// Describe a location whose readability answers a question about privacy grants.
    ///
    /// - Parameters:
    ///     - url: The location to read.
    ///     - subject: What is being read, phrased to be read inside a sentence.
    ///
    public init(url: URL, subject: String) {
        self.subject = subject
        self.url = url
    }

    ///
    /// Read the location and report which of the three states the system answered with.
    ///
    /// A directory answers about being listed and a file about being opened, which is the distinction that matters here: on macOS 27 the client's container can be looked up by a process which is refused every byte inside it, so a probe testing existence would pass while everything built on it fails.
    ///
    /// - Returns: The outcome.
    ///
    public func inspect() -> PrivacyProbeOutcome {
        guard access(url.path(percentEncoded: false), R_OK) != 0 else {
            return .readable
        }

        let code = errno

        switch code {
            case ENOENT, ENOTDIR: return .absent
            default: return .refused(code: code)
        }
    }
}
