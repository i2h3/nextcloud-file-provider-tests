// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Compares one directory level on the server with the same level inside the domain.
///
/// The comparison is deliberately one level deep and never descends on its own, for the same reason ``LocalDirectory`` never walks a tree: enumerating a container is an event the extension under test reacts to, and a check which quietly enumerated everything would destroy the state a test set up.
///
public enum ConvergenceCheck {
    ///
    /// Compare a server-side listing with a local one.
    ///
    /// - Parameters:
    ///     - remote: The entries the server reports for the directory.
    ///     - local: The entries found in the domain, as returned by ``LocalDirectory/children(of:ledger:includesHiddenEntries:)``.
    ///     - ignoredNames: Names to leave out of the comparison. Defaults to ``LocalDirectory/systemEntryNames``, the entries the operating system puts into a domain by itself.
    ///
    /// - Returns: Every disagreement found, in a stable order. An empty result means the two sides agree.
    ///
    public static func compare(remote: [RemoteEntry], local: [LocalNode], ignoredNames: Set<String> = LocalDirectory.systemEntryNames) -> [ConvergenceDifference] {
        let remoteEntries = remote.filter { !ignoredNames.contains($0.name) }
        let localEntries = local.filter { !ignoredNames.contains($0.name) }

        var remainingLocal = [Data: LocalNode]()

        for entry in localEntries {
            remainingLocal[key(of: entry.name)] = entry
        }

        var differences = [ConvergenceDifference]()

        for entry in remoteEntries.sorted(by: { $0.name < $1.name }) {
            guard let match = matchingLocalEntry(for: entry.name, in: remainingLocal) else {
                differences.append(.missingLocally(name: entry.name))

                continue
            }

            remainingLocal.removeValue(forKey: key(of: match.name))

            if key(of: match.name) != key(of: entry.name) {
                differences.append(.nameNormalizationDiffers(remote: entry.name, local: match.name))
            }

            let localIsDirectory = match.kind == .directory

            guard entry.isDirectory == localIsDirectory else {
                differences.append(.kindDiffers(name: entry.name, remoteIsDirectory: entry.isDirectory, localIsDirectory: localIsDirectory))

                continue
            }

            guard !entry.isDirectory, let remoteSize = entry.size, remoteSize != match.size else {
                continue
            }

            differences.append(.sizeDiffers(name: entry.name, remote: remoteSize, local: match.size))
        }

        for name in remainingLocal.values.map(\.name).sorted() {
            differences.append(.missingRemotely(name: name))
        }

        return differences
    }

    ///
    /// Find the local entry which corresponds to a server-side name.
    ///
    /// A byte-exact match wins. Only when there is none is the name compared in its precomposed form, so that a difference in Unicode normalization is found and reported rather than mistaken for a missing file.
    ///
    /// - Parameters:
    ///     - name: The name the server reports.
    ///     - candidates: The local entries which have not been matched yet, keyed by ``key(of:)``.
    ///
    /// - Returns: The corresponding local entry, if there is one.
    ///
    private static func matchingLocalEntry(for name: String, in candidates: [Data: LocalNode]) -> LocalNode? {
        if let exact = candidates[key(of: name)] {
            return exact
        }

        let normalized = key(of: name.precomposedStringWithCanonicalMapping)

        return candidates.values.first { key(of: $0.name.precomposedStringWithCanonicalMapping) == normalized }
    }

    ///
    /// The comparable form of a name.
    ///
    /// Names are compared as the bytes they are made of, not as Swift compares strings. Swift's own equality treats a precomposed and a decomposed spelling as the same string, which is precisely the difference these tests exist to notice: macOS hands out decomposed names while the server stores whatever it was given.
    ///
    /// - Parameters:
    ///     - name: The name to reduce.
    ///
    /// - Returns: The bytes of the name.
    ///
    private static func key(of name: String) -> Data {
        Data(name.utf8)
    }
}
