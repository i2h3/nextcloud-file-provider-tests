// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation
import ServerHarness

///
/// Removes what ``Prepare`` left running.
///
/// The counterpart of preparing a session, and the reason preparing one writes down what it deployed: containers which nobody recorded can only be found by guessing at Docker, and a Nextcloud container costs real memory for as long as it is up.
///
struct Teardown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "teardown",
        abstract: "Delete the containers a prepared session left running."
    )

    ///
    /// Where the session was recorded.
    ///
    @Option(name: .long, help: "The artifacts directory the session was prepared in.")
    var artifacts: String = ".artifacts"

    ///
    /// Whether the desktop client is left as it is.
    ///
    @Flag(name: .long, help: "Do not quit the desktop client.")
    var keepClientRunning = false

    ///
    /// Tear the session down.
    ///
    /// - Throws: Whatever deleting the containers raises.
    ///
    func run() async throws {
        if !keepClientRunning {
            try? await DesktopClient.quit()
        }

        let removed = try await Self.removeContainers(describedBy: SessionDirectory(artifacts: artifacts))

        Console.log(removed == 0 ? "No prepared session was found." : "Removed \(removed) container(s).")
    }

    ///
    /// Delete the containers a session recorded, if it recorded any.
    ///
    /// Failures are reported rather than raised: a container which has already gone, by hand or by a restart of Docker, should not stop the session being forgotten.
    ///
    /// - Parameters:
    ///     - session: The session to tear down.
    ///
    /// - Returns: How many containers were deleted.
    ///
    /// - Throws: Nothing at present, but declared so that callers keep the `await` and the intent.
    ///
    @discardableResult
    static func removeContainers(describedBy session: SessionDirectory) async throws -> Int {
        let servers = session.read()

        guard !servers.isEmpty else {
            return 0
        }

        var removed = 0

        for server in servers {
            do {
                try await ManagedServer.delete(containerIdentifier: server.containerIdentifier)
                removed += 1
            } catch {
                Console.log("Failed to delete the container of \(server.description): \(error)")
            }
        }

        session.clear()

        return removed
    }
}
