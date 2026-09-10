// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``ClientConfigurationFile``.
///
/// The File Provider mode flag decides whether an account becomes a domain at all, and the account listing decides what a person is asked about before a reset removes anything. Both are read from a file whose format belongs to the client, so both are pinned down here against handwritten examples.
///
@Suite("Client configuration file")
struct ClientConfigurationFileTests {
    ///
    /// A configuration with two accounts, in the shape the client writes.
    ///
    static let configured = """
    [General]
    macFileProviderModeEnabled=true

    [Accounts]
    version=13
    0\\url=https://cloud.example.com
    0\\dav_user=alice
    1\\url=http://localhost:8080
    1\\dav_user=bob
    """

    ///
    /// Write a configuration to a temporary file and run a body against it.
    ///
    /// - Parameters:
    ///     - contents: The configuration to write.
    ///     - body: What to run against the written file.
    ///
    /// - Throws: Whatever writing or the body raises.
    ///
    static func withConfiguration(_ contents: String, _ body: (URL) throws -> Void) throws {
        let url = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "nextcloud.cfg", directoryHint: .notDirectory)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        try Data(contents.utf8).write(to: url)
        try body(url)
    }

    @Test
    func `Configured accounts are listed as user and host.`() throws {
        try Self.withConfiguration(Self.configured) { url in
            #expect(ClientConfigurationFile.accounts(in: url) == ["alice@cloud.example.com", "bob@localhost"])
        }
    }

    @Test
    func `A configuration without accounts lists none.`() throws {
        try Self.withConfiguration("[Accounts]\nversion=13\n") { url in
            #expect(ClientConfigurationFile.accounts(in: url).isEmpty)
        }
    }

    @Test
    func `A configuration file which does not exist lists no accounts rather than failing.`() {
        #expect(ClientConfigurationFile.accounts(in: URL(filePath: "/nowhere/nextcloud.cfg")).isEmpty)
    }

    @Test
    func `The File Provider mode flag is recognised.`() throws {
        try Self.withConfiguration(Self.configured) { url in
            #expect(ClientConfigurationFile.isFileProviderModeEnabled(in: url))
        }

        try Self.withConfiguration("[General]\nmacFileProviderModeEnabled=false\n") { url in
            #expect(!ClientConfigurationFile.isFileProviderModeEnabled(in: url))
        }

        try Self.withConfiguration("[General]\nmonoIcons=true\n") { url in
            #expect(!ClientConfigurationFile.isFileProviderModeEnabled(in: url))
        }
    }

    @Test
    func `A seeded configuration switches File Provider mode on and configures nothing else.`() throws {
        let url = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "nextcloud.cfg", directoryHint: .notDirectory)

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        try ClientConfigurationFile.writeFileProviderModeOnly(to: url)

        #expect(ClientConfigurationFile.isFileProviderModeEnabled(in: url))
        #expect(ClientConfigurationFile.accounts(in: url).isEmpty)
    }
}
