// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads a single directory level inside a File Provider domain.
///
/// There is deliberately no recursive walk anywhere in this harness. Descending is always an explicit step in the test, because each level's first read is an event the extension under test reacts to, and a helper which quietly walked a whole tree would enumerate containers no test asked about and make a class of assertions meaningless.
///
public enum LocalDirectory {
    ///
    /// The entries which belong to the operating system rather than to the account.
    ///
    /// Every File Provider domain root holds a `.Trash` the system creates, and Finder leaves `.DS_Store` wherever it has looked. Neither has a counterpart on the server, so a comparison which did not know about them would report every domain as out of sync.
    ///
    public static let systemEntryNames: Set<String> = [".DS_Store", ".Trash"]

    ///
    /// List one directory level.
    ///
    /// - Parameters:
    ///     - directory: The directory to read.
    ///     - ledger: The ledger to record this enumeration in.
    ///     - includesHiddenEntries: Whether entries whose name starts with a dot are included. Defaults to `true`, because noise like `.DS_Store` is part of what is under test.
    ///
    /// - Returns: The entries, sorted by name, described without materializing any of them.
    ///
    /// - Throws: Whatever `FileManager` raises if the directory cannot be read.
    ///
    public static func children(of directory: URL, ledger: EnumerationLedger, includesHiddenEntries: Bool = true) throws -> [LocalNode] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        ledger.record(directory, entryCount: names.count)

        return try names
            .filter { includesHiddenEntries || !$0.hasPrefix(".") }
            .sorted()
            // `compactMap` here would drop an entry the system refused to describe, so a child nobody was allowed to stat would vanish from a listing which is then compared against the server. Absence is still dropped; inability now propagates.
            .compactMap { try LocalNode.at(directory.appending(path: $0, directoryHint: .inferFromPath)) }
    }

    ///
    /// Check whether something exists at a location, without enumerating its parent.
    ///
    /// - Parameters:
    ///     - url: The location to check.
    ///
    /// - Returns: `true` if anything is there.
    ///
    /// - Throws: ``LocalInspectionError`` if the system would not say.
    ///
    public static func exists(_ url: URL) throws -> Bool {
        try LocalNode.at(url) != nil
    }
}
