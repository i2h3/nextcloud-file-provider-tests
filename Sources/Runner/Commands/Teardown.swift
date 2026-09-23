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
    var artifacts: String = "Artifacts"

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

        let outcome = try await Self.removeContainers(describedBy: SessionDirectory(artifacts: artifacts))

        switch (outcome.found, outcome.removed) {
            case (0, _):
                Console.log("No prepared session was found.")

            case let (found, removed) where removed == found:
                Console.log("Removed \(removed) container(s).")

            case let (found, removed):
                // Said as its own case, because it used to be the first one. A session whose containers all failed to delete reported "No prepared session was found" — which is the opposite of what happened, and was followed by the record of them being erased.
                Console.log("Found \(found) container(s) and removed \(removed). The rest are still running and are still recorded, so this command can be run again.")
        }
    }

    ///
    /// Delete the containers a session recorded, if it recorded any.
    ///
    /// Failures are reported rather than raised: a container which has already gone, by hand or by a restart of Docker, should not stop the session being forgotten.
    ///
    /// The session is forgotten only when there is nothing left in it. It used to be cleared unconditionally, on the reasoning above — but that reasoning covers a container which is *already gone*, and a deletion failing because Docker is unreachable or the daemon is busy leaves the container running with its identifier the only way back to it. Erasing the record there turns a retryable failure into a container nobody can name, and the run after it deploys beside it.
    ///
    /// - Parameters:
    ///     - session: The session to tear down.
    ///
    /// - Returns: How many containers the session recorded and how many were deleted.
    ///
    /// - Throws: Nothing at present, but declared so that callers keep the `await` and the intent.
    ///
    @discardableResult
    static func removeContainers(describedBy session: SessionDirectory) async throws -> (found: Int, removed: Int) {
        let servers = session.read()

        guard !servers.isEmpty else {
            return (found: 0, removed: 0)
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

        guard removed == servers.count else {
            return (found: servers.count, removed: removed)
        }

        session.clear()

        return (found: servers.count, removed: removed)
    }
}
