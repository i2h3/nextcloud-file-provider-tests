// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads what the system itself logged about the File Provider.
///
/// A failing synchronisation usually has three accounts of what happened: the client's own log, the server's log, and the operating system's. The last one is the only place which shows the extension being started, throttled or killed, which is why it is part of every diagnostics bundle.
///
public enum UnifiedLogReader {
    ///
    /// The predicate selecting everything the File Provider subsystem logged.
    ///
    public static let fileProviderPredicate = #"subsystem == "com.apple.FileProvider""#

    ///
    /// Read recent log entries.
    ///
    /// - Parameters:
    ///     - predicate: The predicate selecting the entries. Defaults to ``fileProviderPredicate``.
    ///     - duration: How far back to read.
    ///
    /// - Returns: The log output, or a note explaining why it could not be read.
    ///
    public static func recent(predicate: String = fileProviderPredicate, duration: Duration = .seconds(600)) async -> String {
        let minutes = max(1, Int(duration.components.seconds / 60))
        let arguments = ["show", "--predicate", predicate, "--last", "\(minutes)m", "--style", "compact", "--info"]

        do {
            let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/log"), arguments: arguments)

            guard result.isSuccess else {
                return "The unified log could not be read (exit \(result.exitCode)): \(result.standardError)"
            }

            return result.standardOutput
        } catch {
            return "The unified log could not be read: \(error)"
        }
    }
}
