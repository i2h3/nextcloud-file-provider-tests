// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation

///
/// Returns the machine to a state in which no Nextcloud account is configured.
///
/// This is what a run does before its first test, offered separately so that a machine can be cleaned up after an interrupted run without starting another one.
///
struct Reset: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Remove every configured Nextcloud account, domain and credential from this machine."
    )

    ///
    /// Where to keep the copy of the configuration which is removed.
    ///
    @Option(name: .long, help: "Directory to keep a copy of the removed configuration in.")
    var artifacts: String = ".artifacts"

    ///
    /// Run the reset.
    ///
    /// - Throws: Whatever the reset raises.
    ///
    func run() async throws {
        let backupDirectory = URL(filePath: artifacts, directoryHint: .isDirectory).appending(path: "client-configuration-backup", directoryHint: .isDirectory)
        let didReset = try await ClientReset.perform(backingUpTo: backupDirectory) { inventory in
            Confirmation.approveReset(of: inventory, isPreApproved: RunEnvironment.isDestructiveAllowedByEnvironment())
        }

        Console.log(didReset ? "The machine was reset." : "Nothing was removed.")
    }
}
