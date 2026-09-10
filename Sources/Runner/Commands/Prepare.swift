// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation
import ServerHarness

///
/// Deploys the servers and leaves them running, so that the tests can be started from somewhere else.
///
/// This is the half of ``Run`` which sets the stage, without the half which starts `swift test`. It exists for Xcode: the debugger is the reason to run a suite from there, and a breakpoint in a test is worth far more than a tidy command line when a File Provider behaves in a way nobody predicted. Xcode cannot deploy the containers, and the matrix is different every time because the ports are assigned when the containers start, so the servers are deployed here and described in a file whose path does not change.
///
/// The containers are left behind on purpose. ``Teardown`` removes them again.
///
struct Prepare: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Deploy the servers and leave them running, for starting the tests from Xcode."
    )

    ///
    /// Where logs, attachments and reports of the session are collected.
    ///
    @Option(name: .long, help: "Directory to collect logs, attachments and reports in.")
    var artifacts: String = ".artifacts"

    ///
    /// Whether a client the system policy rejects is accepted as the subject.
    ///
    @Flag(name: .long, help: "Accept a client the system policy rejects, such as a development build.")
    var allowDevelopmentClient = false

    ///
    /// Whether the machine-level reset of the desktop client is skipped.
    ///
    @Flag(name: .long, help: "Do not touch the desktop client on this machine.")
    var noClientReset = false

    ///
    /// Whether every release is additionally deployed with the High Performance Backend for Files.
    ///
    @Flag(name: .long, help: "Also deploy every release with push notifications, as a second matrix entry.")
    var withPush = false

    ///
    /// The releases to deploy.
    ///
    @Option(name: .long, parsing: .upToNextOption, help: "The server releases to deploy. Defaults to the current one and the one before it, derived from what `latest` turns out to be.")
    var tags: [String] = []

    ///
    /// Deploy and report.
    ///
    /// - Throws: Whatever preflight or deployment raises.
    ///
    func run() async throws {
        let session = SessionDirectory(artifacts: artifacts)

        let report = await Preflight.checkMachine(allowingUnnotarizedClient: allowDevelopmentClient)
        Console.log(report.description)

        guard report.isSatisfied else {
            throw PreflightError(report: report)
        }

        // A session which is already up would otherwise leak its containers the moment this one overwrites its description.
        try await Teardown.removeContainers(describedBy: session)

        if noClientReset {
            Console.log("Leaving the desktop client alone, as asked. Suites which need a configured account will fail.")
        } else {
            let didReset = try await ClientReset.perform(backingUpTo: session.directory.appending(path: "client-configuration-backup", directoryHint: .isDirectory)) { inventory in
                Confirmation.approveReset(of: inventory, isPreApproved: RunEnvironment.isDestructiveAllowedByEnvironment())
            }

            guard didReset else {
                throw RunError.resetDeclined
            }
        }

        let servers = try await ServerMatrix.deploy(tags: tags, includesPush: withPush) { Console.log($0) }

        try session.write(servers.map(\.descriptor))
        Console.log()
        Console.log(instructions(for: session))
    }

    ///
    /// What to do with the servers which are now running.
    ///
    /// - Parameters:
    ///     - session: The session which was just written.
    ///
    /// - Returns: The text to print.
    ///
    private func instructions(for session: SessionDirectory) -> String {
        var lines = [String]()

        lines.append("The servers are running and described in:")
        lines.append("  \(session.matrixFile.path(percentEncoded: false))")
        lines.append("")
        lines.append("Set these three variables once in Xcode, under Product, Scheme, Edit Scheme, Test, Arguments.")
        lines.append("None of them change between sessions, so this is a one-time setup:")
        lines.append("")
        lines.append("  \(RunEnvironment.matrixFileVariableName)          \(session.matrixFile.path(percentEncoded: false))")
        lines.append("  \(RunEnvironment.allowDestructiveVariableName)         1")
        lines.append("  \(RunEnvironment.allowUnnotarizedClientVariableName)  1")
        lines.append("")
        lines.append("Xcode itself needs Full Disk Access, and has to be restarted after being granted it,")
        lines.append("because a privacy grant only applies to a newly launched process.")
        lines.append("")
        lines.append("Turn parallel execution off in the same scheme, under Test, Options. The suites share one")
        lines.append("desktop client and one File Provider domain at a time, so running them at once cannot work.")
        lines.append("")
        lines.append("When you are done:")
        lines.append("")
        lines.append("  swift run tests teardown")

        return lines.joined(separator: "\n")
    }
}
