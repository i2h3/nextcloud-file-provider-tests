// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads the per-domain settings the File Provider extension writes into its application group.
///
/// The extension records values such as the server address, the user and the user identifier per domain identifier in the container shared through ``ClientPaths/applicationGroupIdentifier``. They are the only place outside the client itself which connects a domain directory to the account behind it, which makes them the cross-check for what ``DomainLocator`` found by comparing directories.
///
/// The exact schema is the client's private business and may change between releases, so everything is returned as it is found instead of being modelled. What is read here is only ever used for diagnostics and for confirming an identification, never as the primary source of truth.
///
public enum DomainDefaults {
    ///
    /// The property list files the extension keeps its defaults in.
    ///
    /// - Returns: One URL per property list found in the group container's preferences directory.
    ///
    public static func propertyListURLs() -> [URL] {
        let preferences = ClientPaths.groupContainer.appending(path: "Library/Preferences", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path(percentEncoded: false))) ?? []

        return names
            .filter { $0.hasSuffix(".plist") }
            .sorted()
            .map { preferences.appending(path: $0, directoryHint: .notDirectory) }
    }

    ///
    /// Everything the extension has recorded, merged across its property lists.
    ///
    /// - Returns: The recorded values, keyed as the extension keyed them.
    ///
    public static func all() -> [String: Any] {
        var merged = [String: Any]()

        for url in propertyListURLs() {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }

            guard let contents = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }

            merged.merge(contents) { existing, _ in existing }
        }

        return merged
    }

    ///
    /// A readable dump of everything the extension has recorded.
    ///
    /// - Returns: One `key = value` line per recorded value, sorted by key.
    ///
    public static func dump() -> String {
        all()
            .sorted { $0.key < $1.key }
            .map { "\($0.key) = \($0.value)" }
            .joined(separator: "\n")
    }
}
