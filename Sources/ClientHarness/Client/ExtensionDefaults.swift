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
    /// - Returns: What reading the switch back found. Only ``ExtensionDefaultState/off`` means it is gone; ``ExtensionDefaultState/unreadable`` means the removal could not be confirmed, which used to be reported as success.
    ///
    @discardableResult
    static func clear(_ key: String) async -> ExtensionDefaultState {
        _ = try? await ProcessRunner.run(executable, arguments: ["delete", ClientPaths.fileProviderExtensionBundleIdentifier, key])

        return await state(of: key)
    }

    ///
    /// Whether a switch is on.
    ///
    /// - Parameters:
    ///     - key: The switch to read.
    ///
    /// - Returns: `true` only if the value is present and reads as true. Defaults which cannot be read at all count as off, because the alternative is a harness which fails on every machine where the client has never run. A caller which needs to know the difference asks ``state(of:)``.
    ///
    static func isEnabled(_ key: String) async -> Bool {
        await state(of: key) == .on
    }

    ///
    /// Read a switch, saying so when it cannot be read.
    ///
    /// `defaults read` fails both for a switch which is not set and for a domain it is not allowed to open, and those two have to be told apart: one is the ordinary state of a machine where the client has never run, and the other is a machine whose answers cannot be trusted. Only the first should let ``clear(_:)`` report success.
    ///
    /// They are told apart by what `defaults` complains about, and it has more than one way of saying "not set" depending on how much is missing and which of its own code paths answered:
    ///
    /// - `The domain/default pair of (…, …) does not exist`
    /// - `Error: Domain '…' not found.` — the ordinary case where the extension has never run
    /// - `Error: Could not find key '…' in domain '…'.` — the domain exists and the key does not
    ///
    /// All of them mean not set. Any other failure is a failure to look.
    ///
    /// Every string is pinned by a test, because they are macOS's wording rather than ours and a release which reworded them would turn every machine into an unreadable one, quietly and everywhere at once. The list was two strings until a run found the third — and found it in one attempt only because ``ExtensionDefaultState/unreadable(_:)`` carries what was said. Enumerating a vendor's error messages is a poor way to ask a question and it is the only one available: these preferences live inside another application's sandbox container, which is why the tool is shelled out to at all rather than read through `CFPreferences` from this process.
    ///
    /// - Parameters:
    ///     - key: The switch to read.
    ///
    /// - Returns: The state.
    ///
    static func state(of key: String) async -> ExtensionDefaultState {
        let result: ProcessResult

        do {
            result = try await ProcessRunner.run(executable, arguments: ["read", ClientPaths.fileProviderExtensionBundleIdentifier, key])
        } catch {
            return .unreadable("the defaults tool could not be run: \(error)")
        }

        guard result.isSuccess else {
            guard isAbsence(result.standardError) else {
                return .unreadable("""
                `defaults read \(ClientPaths.fileProviderExtensionBundleIdentifier) \(key)` exited \(result.exitCode) saying \(quoted(result.standardError, or: result.standardOutput))
                """)
            }

            return .off
        }

        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? .on : .off
    }

    ///
    /// What a command said, for a message, or that it said nothing.
    ///
    /// Both streams, because which one carries a complaint is the tool's business and an empty message is the one answer nobody can act on.
    ///
    /// - Parameters:
    ///     - message: What it wrote to standard error.
    ///     - fallback: What it wrote to standard output.
    ///
    /// - Returns: The text, quoted, or a statement that there was none.
    ///
    static func quoted(_ message: String, or fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty else {
            return "\"\(trimmed)\""
        }

        let alternative = fallback.trimmingCharacters(in: .whitespacesAndNewlines)

        return alternative.isEmpty ? "nothing at all" : "\"\(alternative)\" on its output"
    }

    ///
    /// Whether what `defaults` complained about was a value which is not there.
    ///
    /// - Parameters:
    ///     - message: What it wrote to standard error.
    ///
    /// - Returns: `true` if the complaint is an absence rather than a refusal.
    ///
    static func isAbsence(_ message: String) -> Bool {
        let complaint = message.lowercased()

        return absenceComplaints.contains { complaint.contains($0) }
    }

    ///
    /// The ways `defaults` says a value is not set, in the words it uses.
    ///
    /// Lowercased and matched as fragments, so that a message which gains a prefix or a full stop still reads as the same answer. Deliberately narrow: each one is a phrase about something missing, and none of them would be produced by a refusal to look.
    ///
    static let absenceComplaints = ["does not exist", "not found", "could not find key"]
}
