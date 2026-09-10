// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import NextcloudContainerManager

///
/// Copies the server's own log into a diagnostics bundle.
///
/// A failing synchronisation has three accounts of what happened, and this is the one the client cannot see. It lives here rather than in ``DiagnosticsBundle`` because reaching into a container is the server harness's business, while the bundle itself stays free of any dependency on Docker.
///
enum NextcloudServerLog {
    ///
    /// Copy the log of a server into a directory.
    ///
    /// - Parameters:
    ///     - server: The server to copy the log of.
    ///     - directory: The directory to copy it into. It is created if it does not exist.
    ///
    /// - Returns: The location of the copy.
    ///
    /// - Throws: Whatever copying raises.
    ///
    @discardableResult
    static func copy(of server: ServerUnderTest, into directory: URL) async throws -> URL {
        let source = try await NextcloudContainerManager.logFile(inContainer: server.containerIdentifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "nextcloud-server.log", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        try? FileManager.default.removeItem(at: source)

        return destination
    }
}
