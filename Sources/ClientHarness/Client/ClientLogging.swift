// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Turns the File Provider extension's debug logging on for a run.
///
/// The extension's own log is the only account of the half of the conversation the client never sees: every request the system made of it, and what it answered. At its default level it records little of that, and a release build records less still, so a run which is trying to explain why a file went the way it did is reading the wrong half of the story.
///
/// This is switched on for every clean room rather than left to whoever is debugging, because the interesting failures are the ones nobody expected and so nobody turned logging on for. It costs disk and a little speed; both are cheaper than reproducing a failure a second time.
///
public enum ClientLogging {
    ///
    /// The user defaults key the extension reads.
    ///
    public static let debugLoggingKey = "debugLoggingEnabled"

    ///
    /// Make the extension record debug-level messages.
    ///
    /// - Throws: ``ProcessRunnerError`` if the value cannot be written.
    ///
    public static func enableDebugLogging() async throws {
        try await ExtensionDefaults.enable(debugLoggingKey)
    }

    ///
    /// Return the extension to whatever it logs by default.
    ///
    public static func disableDebugLogging() async {
        await ExtensionDefaults.clear(debugLoggingKey)
    }

    ///
    /// Whether the extension is recording debug-level messages.
    ///
    /// - Returns: `true` if the value is set and reads as true.
    ///
    public static func isDebugLoggingEnabled() async -> Bool {
        await ExtensionDefaults.isEnabled(debugLoggingKey)
    }
}
