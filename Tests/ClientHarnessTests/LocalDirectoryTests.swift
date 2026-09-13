// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``LocalNode`` and ``LocalDirectory`` against ordinary files.
///
/// A local temporary directory is not a File Provider domain, so nothing here can be dataless. What is verified is the part which has to hold everywhere: that inspection reads one level, records it, and never follows a symbolic link or descends on its own.
///
@Suite("Local inspection")
struct LocalDirectoryTests {
    ///
    /// Build a small tree in a temporary directory and run a body against it.
    ///
    /// - Parameters:
    ///     - body: What to run against the created directory.
    ///
    /// - Throws: Whatever creating the tree or the body raises.
    ///
    static func withTree(_ body: (URL) throws -> Void) throws {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "folder", directoryHint: .isDirectory), withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try Data("hello".utf8).write(to: root.appending(path: "a.txt", directoryHint: .notDirectory))
        try Data("nested".utf8).write(to: root.appending(path: "folder/b.txt", directoryHint: .notDirectory))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link", directoryHint: .notDirectory), withDestinationURL: root.appending(path: "a.txt", directoryHint: .notDirectory))

        try body(root)
    }

    @Test
    func `Only one level is read, and the enumeration is recorded.`() throws {
        try Self.withTree { root in
            let ledger = EnumerationLedger()
            let children = try LocalDirectory.children(of: root, ledger: ledger)

            #expect(children.map(\.name) == ["a.txt", "folder", "link"])
            #expect(ledger.hasEnumerated(root))
            #expect(!ledger.hasEnumerated(root.appending(path: "folder", directoryHint: .isDirectory)))
        }
    }

    @Test
    func `A symbolic link is reported as one instead of being followed.`() throws {
        try Self.withTree { root in
            let node = try #require(try LocalNode.at(root.appending(path: "link", directoryHint: .notDirectory)))

            #expect(node.kind == .symbolicLink)
        }
    }

    @Test
    func `An ordinary file is never dataless.`() throws {
        try Self.withTree { root in
            let node = try #require(try LocalNode.at(root.appending(path: "a.txt", directoryHint: .notDirectory)))

            #expect(node.kind == .file)
            #expect(node.size == 5)
            #expect(!node.isDataless)
        }
    }

    @Test
    func `Nothing is reported where nothing exists, without enumerating the parent.`() throws {
        try Self.withTree { root in
            try #expect(LocalNode.at(root.appending(path: "missing", directoryHint: .notDirectory)) == nil)
            try #expect(!LocalDirectory.exists(root.appending(path: "missing", directoryHint: .notDirectory)))
        }
    }

    ///
    /// The distinction the whole primitive turns on, and the one it used to throw away.
    ///
    /// A refused `lstat` returned the same `nil` as a missing file, so `LocalDirectory.exists` answered `false`, a listing quietly dropped the entry, and every assertion above was told the item was not there. That is the preflight's `denied`-versus-`empty` confusion again, one layer below the preflight that exists to prevent it.
    ///
    @Test
    func `A location the process may not inspect is not reported as empty.`() throws {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let closed = root.appending(path: "closed", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: closed.appending(path: "inside.txt", directoryHint: .notDirectory))

        // Nothing may be resolved through a directory with no execute bit, so an `lstat` of a path inside it is refused rather than answered.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path(percentEncoded: false))

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: closed.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: root)
        }

        let inside = closed.appending(path: "inside.txt", directoryHint: .notDirectory)

        #expect(throws: LocalInspectionError.self) {
            try LocalNode.at(inside)
        }

        #expect(throws: LocalInspectionError.self) {
            try LocalDirectory.exists(inside)
        }

        // A location which genuinely holds nothing still answers, and answers no.
        #expect(try LocalNode.at(root.appending(path: "absent", directoryHint: .notDirectory)) == nil)
    }
}
