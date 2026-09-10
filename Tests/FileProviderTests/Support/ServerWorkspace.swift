// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import NextcloudContainerManager
import Rainmaker
import ServerHarness
import Testing

///
/// A test's own user on a server, without the desktop client.
///
/// This is the half of a ``CleanRoom`` which does not involve the client at all. It exists so that everything the server side of the harness does — deploying a release, switching off the demo content, creating a user, issuing an app password, talking WebDAV as that user — can be exercised and kept honest even while the client cannot be configured headlessly.
///
struct ServerWorkspace {
    ///
    /// A Rainmaker client authenticated as the administrator of the server.
    ///
    let administration: Server

    ///
    /// A Rainmaker client authenticated as this test's own user, with its app password.
    ///
    let server: Server

    ///
    /// The server this test runs against.
    ///
    let underTest: ServerUnderTest

    ///
    /// This test's own user.
    ///
    let user: TestUser

    ///
    /// Provision a user, run a test as that user, and delete the user again.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - testName: The test the user belongs to, conventionally `<suite>.<test>`.
    ///     - body: The test itself.
    ///
    /// - Returns: Whatever the body returns.
    ///
    /// - Throws: Whatever provisioning, the body or the cleanup raises.
    ///
    @discardableResult
    static func with<Result>(_ underTest: ServerUnderTest, testName: String, _ body: (ServerWorkspace) async throws -> Result) async throws -> Result {
        let user = try await TestUser.provision(for: testName, on: underTest)

        let workspace = ServerWorkspace(
            administration: Server(address: underTest.serverAddress, password: underTest.adminPassword, user: underTest.adminUser),
            server: user.client(on: underTest),
            underTest: underTest,
            user: user
        )

        do {
            let result = try await body(workspace)
            try await user.delete(on: underTest)

            return result
        } catch {
            try? await user.delete(on: underTest)

            throw error
        }
    }

    ///
    /// Suspend a server for the duration of a body, and let it run again afterwards whatever happens.
    ///
    /// The server is resumed on the way out even when the body fails, because a container left frozen would take every later test in the run down with it.
    ///
    /// - Parameters:
    ///     - underTest: The server to suspend.
    ///     - body: What to do while it is unreachable.
    ///
    /// - Returns: Whatever the body returns.
    ///
    /// - Throws: Whatever suspending, the body or resuming raises.
    ///
    @discardableResult
    static func withServerPaused<Result>(_ underTest: ServerUnderTest, _ body: () async throws -> Result) async throws -> Result {
        try await NextcloudContainerManager.pause(underTest.containerIdentifier)

        do {
            let result = try await body()
            try await NextcloudContainerManager.resume(underTest.containerIdentifier)

            return result
        } catch {
            try? await NextcloudContainerManager.resume(underTest.containerIdentifier)

            throw error
        }
    }

    ///
    /// Write fixture content to a temporary file of a given name, hand it to a body, and remove it afterwards.
    ///
    /// The name matters: Rainmaker's `upload(_:to:force:)` takes the destination **directory** and keeps the local file's name, so the name of this file is the name the item ends up with on the server and, through synchronisation, in the domain.
    ///
    /// - Parameters:
    ///     - name: The file name to use, locally and remotely.
    ///     - size: How large the content should be.
    ///     - seed: The seed determining the content.
    ///     - body: What to do with the file and its fingerprint.
    ///
    /// - Returns: Whatever the body returns.
    ///
    /// - Throws: Whatever writing the file or the body raises.
    ///
    @discardableResult
    static func withFixture<Result>(named name: String, size: Int, seed: UInt64, _ body: (URL, String) async throws -> Result) async throws -> Result {
        let content = ContentFactory.content(size: size, seed: seed)
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try content.write(to: url)

        return try await body(url, ContentFactory.fingerprint(of: content))
    }
}
