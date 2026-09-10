// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What the desktop client currently has on this machine.
///
/// This is what ``ClientReset`` is about to remove, and what it prints and asks about before it does. The tests are meant to be written and run on an ordinary developer machine, so the guard against wiping a configuration somebody cares about is an informed confirmation rather than a refusal to run.
///
public struct ClientInventory: Sendable, CustomStringConvertible {
    ///
    /// The accounts found in the client's configuration file, described as `user@host`.
    ///
    public let accounts: [String]

    ///
    /// The File Provider domain directories found under ``ClientPaths/cloudStorage`` which belong to the client.
    ///
    public let domainDirectories: [URL]

    ///
    /// Whether the Keychain holds at least one credential of the client.
    ///
    public let hasKeychainCredentials: Bool

    ///
    /// Whether the client or its File Provider extension is running.
    ///
    public let isRunning: Bool

    ///
    /// The state directories which exist and would be removed.
    ///
    public let stateDirectories: [URL]

    ///
    /// Whether there is anything at all to remove.
    ///
    public var isEmpty: Bool {
        accounts.isEmpty && domainDirectories.isEmpty && stateDirectories.isEmpty && !hasKeychainCredentials
    }

    public var description: String {
        guard !isEmpty else {
            return "No desktop client state found on this machine."
        }

        var lines = ["The following desktop client state was found and would be removed:"]

        if !accounts.isEmpty {
            lines.append("  Accounts: \(accounts.joined(separator: ", "))")
        }

        for directory in domainDirectories {
            lines.append("  Domain: \(directory.path(percentEncoded: false))")
        }

        for directory in stateDirectories {
            lines.append("  State: \(directory.path(percentEncoded: false))")
        }

        if hasKeychainCredentials {
            lines.append("  Keychain: entries of service \"\(ClientPaths.keychainService)\"")
        }

        if isRunning {
            lines.append("  The client is currently running and would be quit.")
        }

        return lines.joined(separator: "\n")
    }

    ///
    /// Create an inventory.
    ///
    /// - Parameters:
    ///     - accounts: The accounts found in the client's configuration file.
    ///     - domainDirectories: The File Provider domain directories belonging to the client.
    ///     - stateDirectories: The state directories which exist.
    ///     - hasKeychainCredentials: Whether the Keychain holds at least one credential of the client.
    ///     - isRunning: Whether the client or its extension is running.
    ///
    public init(accounts: [String], domainDirectories: [URL], stateDirectories: [URL], hasKeychainCredentials: Bool, isRunning: Bool) {
        self.accounts = accounts
        self.domainDirectories = domainDirectories
        self.hasKeychainCredentials = hasKeychainCredentials
        self.isRunning = isRunning
        self.stateDirectories = stateDirectories
    }
}
