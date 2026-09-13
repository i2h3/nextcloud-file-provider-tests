// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Collects everything needed to understand a failure, without changing what failed.
///
/// The rule which shapes this type: collecting diagnostics must not alter the state being diagnosed. Only directories which the test already enumerated are listed, taken from the ``EnumerationLedger``; everything else is reported as deliberately untouched. Nothing is ever read in a way which would materialize a placeholder.
///
public enum DiagnosticsBundle {
    ///
    /// Gather a bundle into a directory.
    ///
    /// - Parameters:
    ///     - directory: Where to write the bundle. It is created if it does not exist.
    ///     - ledger: The enumeration ledger of the failing test.
    ///     - clientLogDirectory: The directory the client wrote its logs to during the test, if there was one.
    ///     - focus: The item the failure was about, if there is a single one.
    ///     - notes: Anything the caller wants recorded, such as the failing expectation.
    ///
    /// - Returns: The directory the bundle was written to.
    ///
    /// - Throws: Whatever writing the bundle raises.
    ///
    @discardableResult
    public static func collect(into directory: URL, ledger: EnumerationLedger, clientLogDirectory: URL? = nil, focus: URL? = nil, notes: [String: String] = [:]) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try write(notesReport(notes), to: directory.appending(path: "notes.txt", directoryHint: .notDirectory))
        try write(ledgerReport(ledger), to: directory.appending(path: "enumeration-ledger.txt", directoryHint: .notDirectory))
        try write(DomainDefaults.dump(), to: directory.appending(path: "file-provider-defaults.txt", directoryHint: .notDirectory))
        try await write(UnifiedLogReader.recent(), to: directory.appending(path: "unified-log.txt", directoryHint: .notDirectory))

        if let focus {
            try write(focusReport(focus), to: directory.appending(path: "focus.txt", directoryHint: .notDirectory))
        }

        if let clientLogDirectory, (try? LocalDirectory.exists(clientLogDirectory)) == true {
            let destination = directory.appending(path: "client-logs", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: clientLogDirectory, to: destination)
        }

        return directory
    }

    ///
    /// Describe the item a failure was about, without materializing it.
    ///
    /// - Parameters:
    ///     - focus: The item to describe.
    ///
    /// - Returns: The report.
    ///
    private static func focusReport(_ focus: URL) -> String {
        let found: LocalNode?

        do {
            found = try LocalNode.at(focus)
        } catch {
            // A bundle is collected when things have already gone wrong, so this reports rather than raises — but it reports which of the two answers it got, because "nothing is there" and "the system would not say" send a reader to different places.
            return "\(error)"
        }

        guard let node = found else {
            return "Nothing exists at \(focus.path(percentEncoded: false))."
        }

        return """
        Path: \(node.url.path(percentEncoded: false))
        Kind: \(node.kind.rawValue)
        Size: \(node.size) bytes
        Allocated blocks: \(node.allocatedBlocks)
        Dataless: \(node.isDataless)
        Flags: \(String(node.flags, radix: 16))
        Modified: \(node.modificationDate.formatted(.iso8601))
        """
    }

    ///
    /// Describe what the test enumerated, and list exactly those directories again.
    ///
    /// - Parameters:
    ///     - ledger: The ledger of the failing test.
    ///
    /// - Returns: The report.
    ///
    private static func ledgerReport(_ ledger: EnumerationLedger) -> String {
        let entries = ledger.entries

        guard !entries.isEmpty else {
            return "The test enumerated no directory."
        }

        var lines = ["Enumerations performed by the test, in order:"]
        lines += entries.map { "  \($0)" }
        lines.append("")
        lines.append("Contents of those directories at the time of collection. Any directory not listed here was deliberately not enumerated and is therefore not shown, so that collecting diagnostics does not change the state being diagnosed.")

        var seen = Set<String>()

        for entry in entries {
            let path = entry.directory.standardizedFileURL.path(percentEncoded: false)

            guard seen.insert(path).inserted else {
                continue
            }

            lines.append("")
            lines.append(path)

            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []

            for name in names.sorted() {
                let child = entry.directory.appending(path: name, directoryHint: .inferFromPath)

                guard let node = try? LocalNode.at(child) ?? nil else {
                    lines.append("  \(name): could not be described")

                    continue
                }

                lines.append("  \(node.kind.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(node.isDataless ? "dataless    " : "materialized") \(String(format: "%10d", node.size)) \(name)")
            }
        }

        return lines.joined(separator: "\n")
    }

    ///
    /// Render the caller's notes.
    ///
    /// - Parameters:
    ///     - notes: The notes to render.
    ///
    /// - Returns: The report.
    ///
    private static func notesReport(_ notes: [String: String]) -> String {
        var lines = ["Collected: \(Date().formatted(.iso8601))"]

        if let version = DesktopClient.installedVersion() {
            lines.append("Client version: \(version)")
        }

        lines += notes.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }

        return lines.joined(separator: "\n")
    }

    ///
    /// Write one report of the bundle.
    ///
    /// - Parameters:
    ///     - contents: What to write.
    ///     - url: Where to write it.
    ///
    /// - Throws: Whatever writing raises.
    ///
    private static func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}
