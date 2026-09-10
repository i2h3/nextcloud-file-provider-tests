// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation

///
/// Reports whether this machine can run the live suites, and what a run would remove.
///
/// Nothing here changes anything. It is the command to run first on a new machine and the command to run when a run fails for a reason which sounds environmental.
///
struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check this machine and report what a run would remove, without changing anything."
    )

    ///
    /// Whether a client the system policy rejects is accepted as the subject.
    ///
    @Flag(name: .long, help: "Accept a client the system policy rejects, such as a development build.")
    var allowDevelopmentClient = false

    ///
    /// Run the checks and print the findings.
    ///
    /// - Throws: ``PreflightError`` if the machine is not ready, so that the exit status reflects it.
    ///
    func run() async throws {
        let report = await Preflight.checkMachine(allowingUnnotarizedClient: allowDevelopmentClient)
        Console.log(report.description)
        Console.log()

        let inventory = try await ClientReset.inventory()
        Console.log(inventory.description)

        guard report.isSatisfied else {
            throw PreflightError(report: report)
        }
    }
}
