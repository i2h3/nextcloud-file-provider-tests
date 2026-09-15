// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``PrivacyProbe``.
///
/// The three outcomes are the point of the type, and only two of them were distinguishable in what it replaces. These pin down that a refusal and an absence do not collapse into each other, using a directory this process owns rather than anything macOS protects, so they answer the same on a machine with every privacy grant and on one with none.
///
@Suite("Privacy probe")
struct PrivacyProbeTests {
    ///
    /// A directory to put the probed files in, removed with the test.
    ///
    /// - Parameters:
    ///     - body: What to do with it.
    ///
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test("A file this process may read is readable.")
    func readableFile() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "readable", directoryHint: .notDirectory)
            try Data("contents".utf8).write(to: url)

            #expect(PrivacyProbe(url: url, subject: "a file").inspect() == .readable)
        }
    }

    @Test("A directory this process may list is readable.")
    func readableDirectory() throws {
        try withTemporaryDirectory { directory in
            #expect(PrivacyProbe(url: directory, subject: "a directory").inspect() == .readable)
        }
    }

    @Test("A file which is not there is absent rather than refused.")
    func absentFile() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "missing", directoryHint: .notDirectory)

            #expect(PrivacyProbe(url: url, subject: "a file").inspect() == .absent)
        }
    }

    @Test("A path below something which is not a directory is absent rather than refused.")
    func absentBelowFile() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appending(path: "file", directoryHint: .notDirectory)
            try Data("contents".utf8).write(to: file)
            let url = file.appending(path: "below", directoryHint: .notDirectory)

            #expect(PrivacyProbe(url: url, subject: "a file").inspect() == .absent)
        }
    }

    @Test("A file this process may not read is refused rather than absent.")
    func refusedFile() throws {
        // The distinction this whole type exists for, and the one the check built on `isReadableFile` could not make: both of these used to be `false`, and a probe whose location macOS had moved reported a machine with the grant as a machine without it.
        try #require(getuid() != 0, "root reads everything, so this test can only mean something for an ordinary user.")

        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "refused", directoryHint: .notDirectory)
            try Data("contents".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path(percentEncoded: false))

            #expect(PrivacyProbe(url: url, subject: "a file").inspect() == .refused(code: EACCES))
        }
    }

    @Test("The locations Full Disk Access is probed with do not include the per-user privacy database.")
    func doesNotProbeTheMovedDatabase() {
        // macOS 27 moved it into `/private/var/containers/Data/ProtectedSystem`, where Full Disk Access does not reach it either, so it cannot answer this question on any macOS any more. It is named here so that restoring it is a deliberate act rather than an oversight.
        let moved = ClientPaths.home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db", directoryHint: .notDirectory)

        #expect(!PrivacyProbe.fullDiskAccess.contains { $0.url == moved })
        #expect(PrivacyProbe.fullDiskAccess.count > 1, "One probe cannot tell a refusal from a location this version of macOS no longer has.")
    }

    @Test("The client's own data is probed where the suite reads it.")
    func probesTheEvidencePaths() {
        // Not stand-ins. Since macOS 27 these are protected separately from Full Disk Access, so a check reading anything else would pass while every test starved.
        #expect(PrivacyProbe.clientApplicationData.contains { $0.url == ClientPaths.configurationFile })
        #expect(PrivacyProbe.clientApplicationData.contains { $0.url == ClientPaths.extensionLogs })
    }
}
