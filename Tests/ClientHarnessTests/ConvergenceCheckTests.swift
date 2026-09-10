// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``ConvergenceCheck``.
///
/// The comparison is the assertion most tests ultimately rest on, so it is exercised here against handmade listings rather than only against a live domain, where a mistake in it would look like a client bug.
///
@Suite("Convergence check")
struct ConvergenceCheckTests {
    ///
    /// Build a local entry for a comparison.
    ///
    /// - Parameters:
    ///     - name: The name of the entry.
    ///     - kind: What kind of entry it is.
    ///     - size: The size in bytes.
    ///
    /// - Returns: The entry.
    ///
    static func local(_ name: String, kind: LocalNodeKind = .file, size: Int64 = 0) -> LocalNode {
        LocalNode(url: URL(filePath: "/domain").appending(path: name), kind: kind, size: size, allocatedBlocks: 0, modificationDate: Date(timeIntervalSince1970: 0), flags: 0)
    }

    @Test
    func `Identical listings agree.`() {
        let remote = [RemoteEntry(name: "a.txt", isDirectory: false, size: 10), RemoteEntry(name: "folder", isDirectory: true, size: nil)]
        let local = [Self.local("a.txt", size: 10), Self.local("folder", kind: .directory)]

        #expect(ConvergenceCheck.compare(remote: remote, local: local).isEmpty)
    }

    @Test
    func `An entry missing on either side is reported.`() {
        let differences = ConvergenceCheck.compare(
            remote: [RemoteEntry(name: "only-remote", isDirectory: false, size: 1)],
            local: [Self.local("only-local", size: 1)]
        )

        #expect(differences.contains(.missingLocally(name: "only-remote")))
        #expect(differences.contains(.missingRemotely(name: "only-local")))
    }

    @Test
    func `A size which does not match is reported.`() {
        let differences = ConvergenceCheck.compare(
            remote: [RemoteEntry(name: "a.txt", isDirectory: false, size: 10)],
            local: [Self.local("a.txt", size: 9)]
        )

        #expect(differences == [.sizeDiffers(name: "a.txt", remote: 10, local: 9)])
    }

    @Test
    func `A file which is a directory on the other side is reported.`() {
        let differences = ConvergenceCheck.compare(
            remote: [RemoteEntry(name: "thing", isDirectory: true, size: nil)],
            local: [Self.local("thing", size: 0)]
        )

        #expect(differences == [.kindDiffers(name: "thing", remoteIsDirectory: true, localIsDirectory: false)])
    }

    @Test
    func `A name which differs only in its Unicode normalization is matched but reported.`() {
        let composed = "Übung.txt".precomposedStringWithCanonicalMapping
        let decomposed = composed.decomposedStringWithCanonicalMapping

        let differences = ConvergenceCheck.compare(
            remote: [RemoteEntry(name: composed, isDirectory: false, size: 3)],
            local: [Self.local(decomposed, size: 3)]
        )

        #expect(differences == [.nameNormalizationDiffers(remote: composed, local: decomposed)])
    }

    @Test
    func `Ignored names take part in neither direction.`() {
        let differences = ConvergenceCheck.compare(
            remote: [RemoteEntry(name: "a.txt", isDirectory: false, size: 1)],
            local: [Self.local("a.txt", size: 1), Self.local(".DS_Store", size: 6148)]
        )

        #expect(differences.isEmpty)
    }
}
