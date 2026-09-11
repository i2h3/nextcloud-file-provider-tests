// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// The command line entry point of the suite.
///
/// The runner owns everything which is the same for every test: the containers of the servers under test, the state of the desktop client on this machine, and the collection of artifacts. Everything which differs per test — the user, the client configuration, the File Provider domain — belongs to the test process, which is the only place that knows the test names those users are derived from.
///
/// Running the tests is the default, so the command reads `swift run tests` rather than repeating a verb.
///
@main
struct Runner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tests",
        abstract: "Run the Nextcloud desktop client File Provider tests against locally deployed servers.",
        subcommands: [Run.self, Report.self, Prepare.self, Teardown.self, Doctor.self, Reset.self],
        defaultSubcommand: Run.self
    )
}
