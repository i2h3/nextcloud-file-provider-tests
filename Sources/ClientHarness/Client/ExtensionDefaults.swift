// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads and writes the boolean switches the File Provider extension takes from its own user defaults.
///
/// The extension is sandboxed, so its preferences live inside its container rather than anywhere this process can reach with a `UserDefaults` suite. The `defaults` tool reaches them, which is why everything here goes through a subprocess rather than through Foundation.
///
/// Each switch is read live by the extension, so a value written here takes effect without restarting anything, and each is process-global rather than per domain.
///
enum ExtensionDefaults {
    ///
    /// The `defaults` tool.
    ///
    static let executable = URL(filePath: "/usr/bin/defaults")

    ///
    /// Turn a switch on.
    ///
    /// - Parameters:
    ///     - key: The switch to set.
    ///
    /// - Throws: ``ProcessRunnerError`` if the value cannot be written.
    ///
    static func enable(_ key: String) async throws {
        try await ProcessRunner.runSuccessfully(executable, arguments: ["write", ClientPaths.fileProviderExtensionBundleIdentifier, key, "-bool", "true"])
    }

    ///
    /// Remove a switch, returning it to whatever the extension does when it is not set.
    ///
    /// Removing rather than writing `false` keeps a machine which was never touched indistinguishable from one which was put back. The outcome is checked rather than the exit status, because removing a key which is not there fails, and fails with the misleading complaint that the whole domain was not found.
    ///
    /// - Parameters:
    ///     - key: The switch to remove.
    ///
    /// - Returns: `true` if the switch is gone afterwards.
    ///
    @discardableResult
    static func clear(_ key: String) async -> Bool {
        _ = try? await ProcessRunner.run(executable, arguments: ["delete", ClientPaths.fileProviderExtensionBundleIdentifier, key])

        return await !isEnabled(key)
    }

    ///
    /// Whether a switch is on.
    ///
    /// - Parameters:
    ///     - key: The switch to read.
    ///
    /// - Returns: `true` only if the value is present and reads as true. Defaults which cannot be read at all count as off, because the alternative is a harness which fails on every machine where the client has never run.
    ///
    static func isEnabled(_ key: String) async -> Bool {
        guard let result = try? await ProcessRunner.run(executable, arguments: ["read", ClientPaths.fileProviderExtensionBundleIdentifier, key]), result.isSuccess else {
            return false
        }

        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }
}
