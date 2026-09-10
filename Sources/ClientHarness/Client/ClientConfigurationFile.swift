// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

//
// Reads the accounts out of a `nextcloud.cfg`.
//
// The file is the client's own INI-style configuration. Only enough of it is parsed to tell a human which accounts are configured, because that is all ``ClientInventory`` needs in order to ask a meaningful question before removing anything.

/// Accounts are never written here — they are created through the client's command line options, so that the tests exercise the same path a real installation takes. The one thing which is written is the application-level File Provider mode, because that flag decides whether an account becomes a File Provider domain at all and there is no command line option for it.
///
public enum ClientConfigurationFile {
    ///
    /// The key of the application-level flag which decides whether accounts are served through the File Provider.
    ///
    /// It lives in the `[General]` section. Without it, or with it switched off, an account is set up as a classic synchronisation folder and no domain ever appears — which is exactly the failure a test would otherwise report as a timeout.
    ///
    public static let fileProviderModeKey = "macFileProviderModeEnabled"

    ///
    /// Write a configuration which switches File Provider mode on and configures nothing else.
    ///
    /// A clean room seeds this before it launches the client, so that the mode is decided by the test rather than by whatever the client defaults to when it finds no configuration at all.
    ///
    /// - Parameters:
    ///     - url: The configuration file to write. Its directory is created if it does not exist.
    ///
    /// - Throws: Whatever creating the directory or writing the file raises.
    ///
    public static func writeFileProviderModeOnly(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let contents = """
        [General]
        \(fileProviderModeKey)=true

        """

        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    ///
    /// Whether the configuration switches File Provider mode on.
    ///
    /// - Parameters:
    ///     - url: The configuration file to read.
    ///
    /// - Returns: `true` if the flag is present and set.
    ///
    public static func isFileProviderModeEnabled(in url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        return contents
            .split(separator: "\n")
            .map { $0.replacingOccurrences(of: " ", with: "") }
            .contains("\(fileProviderModeKey)=true")
    }

    ///
    /// Read the configured accounts.
    ///
    /// - Parameters:
    ///     - url: The configuration file to read.
    ///
    /// - Returns: One `user@host` description per configured account, or an empty array if the file does not exist or holds no account.
    ///
    public static func accounts(in url: URL) -> [String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var hosts = [String: String]()
        var users = [String: String]()

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let statement = line.trimmingCharacters(in: .whitespaces)

            guard let separator = statement.firstIndex(of: "=") else {
                continue
            }

            let key = String(statement[statement.startIndex ..< separator])
            let value = String(statement[statement.index(after: separator)...])

            // Account settings are prefixed with the account's index, as in `0\url` and `0\dav_user`.
            let components = key.split(separator: #"\"#, maxSplits: 1)

            guard components.count == 2 else {
                continue
            }

            let index = String(components[0])

            switch components[1] {
                case "url":
                    hosts[index] = URL(string: value)?.host() ?? value

                case "dav_user", "user":
                    users[index] = value

                default:
                    continue
            }
        }

        return hosts.keys
            .sorted()
            .map { index in
                "\(users[index] ?? "?")@\(hosts[index] ?? "?")"
            }
    }
}
