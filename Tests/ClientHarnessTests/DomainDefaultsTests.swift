// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``DomainDefaults``.
///
/// This type looked in the group container for a long time and found nothing there, so every diagnostics bundle carried an empty file and nobody noticed, because a reader which returns nothing looks exactly like a machine with no domains. What is pinned here is the shape of where it looks, which is the part that was wrong, and the distinction between the two containers which made it easy to get wrong.
///
@Suite("Domain defaults")
struct DomainDefaultsTests {
    ///
    /// A sandboxed extension reaches its own preferences inside its own container. The group container is granted in its entitlements but holds no preferences at all, which is what made the original mistake invisible.
    ///
    @Test
    func `Preferences are looked for in the extension containers rather than in the group container.`() {
        let directories = DomainDefaults.preferencesDirectories()

        #expect(!directories.isEmpty)

        for directory in directories {
            let path = directory.path(percentEncoded: false)

            #expect(path.contains("Library/Containers/"))
            #expect(!path.contains("Group Containers"))
            #expect(path.hasSuffix("Data/Library/Preferences/"))
        }
    }

    ///
    /// The File Provider extension is the one which records which account a domain belongs to, so its container is the one which has to be read.
    ///
    @Test
    func `The File Provider extension is among the containers looked in.`() {
        let paths = DomainDefaults.preferencesDirectories().map { $0.path(percentEncoded: false) }

        #expect(paths.contains { $0.contains(ClientPaths.fileProviderExtensionBundleIdentifier) })
    }

    ///
    /// A container's preferences directory also holds the operating system's own property lists, which are shared by every sandboxed process and say nothing about this client.
    ///
    @Test
    func `Property lists which do not belong to the client are left out.`() throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        for name in ["com.apple.security.plist", "\(ClientPaths.fileProviderExtensionBundleIdentifier).plist", "notes.txt"] {
            try Data().write(to: directory.appending(path: name, directoryHint: .notDirectory))
        }

        let names = try (FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
            .filter { $0.hasSuffix(".plist") && $0.hasPrefix(ClientPaths.bundleIdentifier) }

        #expect(names == ["\(ClientPaths.fileProviderExtensionBundleIdentifier).plist"])
    }

    ///
    /// Reading must never raise on a machine where the client has never run, because a diagnostics bundle is collected precisely when things have gone wrong.
    ///
    @Test
    func `Reading a machine with no extension state yields nothing rather than failing.`() {
        _ = DomainDefaults.all()
        _ = DomainDefaults.dump()
    }
}
