// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads the per-domain settings the File Provider extension writes into its own preferences.
///
/// The extension records values such as the server address, the user and the user identifier per domain identifier. They are the only place outside the client itself which connects a domain directory to the account behind it, which makes them the cross-check for what ``DomainLocator`` found by comparing directories.
///
/// They live in the extension's own sandbox container rather than in the group container shared with the client, which is a distinction worth stating because it is easy to get wrong: the group container is granted in the extension's entitlements and holds no preferences at all, so reading there returns nothing and says nothing about whether anything was found. This type read there until it was noticed that every diagnostics bundle carried an empty file.
///
/// The exact schema is the client's private business and may change between releases, so everything is returned as it is found instead of being modelled. What is read here is only ever used for diagnostics and for confirming an identification, never as the primary source of truth.
///
public enum DomainDefaults {
    ///
    /// The property list files the extensions keep their defaults in.
    ///
    /// - Returns: One URL per property list found in the preferences directory of each extension container, in a stable order.
    ///
    public static func propertyListURLs() -> [URL] {
        preferencesDirectories().flatMap { preferences in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path(percentEncoded: false))) ?? []

            return names
                // A container's preferences directory also holds the operating system's own property lists, which are symbolic links to files shared by every sandboxed process and have nothing to say about this client.
                .filter { $0.hasSuffix(".plist") && $0.hasPrefix(ClientPaths.bundleIdentifier) }
                .sorted()
                .map { preferences.appending(path: $0, directoryHint: .notDirectory) }
        }
    }

    ///
    /// The directories the extensions keep their preferences in.
    ///
    /// A sandboxed process reaches its own preferences inside its container, so there is one of these per extension rather than one shared between them.
    ///
    /// - Returns: The directories, whether or not they exist.
    ///
    public static func preferencesDirectories() -> [URL] {
        ClientPaths.extensionContainers.map { container in
            container.appending(path: "Data/Library/Preferences", directoryHint: .isDirectory)
        }
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
