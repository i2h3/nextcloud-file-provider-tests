// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import ClientHarness
import Foundation
import ServerHarness

///
/// Deploys the servers of the matrix, runs the tests against all of them in one process, and tears everything down again.
///
/// The server release is a test parameter rather than a separate run: one container per release, all of them live at the same time, and a single `swift test` covering the whole matrix. Only the containers and the machine-level reset are owned here, because everything else differs per test case.
///
struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Deploy the servers, run the tests against them, then tear everything down."
    )

    ///
    /// Where logs, attachments and reports of this run are collected.
    ///
    @Option(name: .long, help: "Directory to collect logs, attachments and reports in.")
    var artifacts: String = ".artifacts"

    ///
    /// A filter passed on to the test process.
    ///
    @Option(name: .long, help: "Only run tests whose name matches this pattern.")
    var filter: String?

    ///
    /// Whether a client the system policy rejects is accepted as the subject.
    ///
    @Flag(name: .long, help: "Accept a client the system policy rejects, such as a development build. Recorded in the report, because it is not what a user would install.")
    var allowDevelopmentClient = false

    ///
    /// Whether the machine-level reset of the desktop client is skipped.
    ///
    @Flag(name: .long, help: "Do not touch the desktop client on this machine. Only useful for suites which need no client, such as the server provisioning ones.")
    var noClientReset = false

    ///
    /// Whether the containers are kept after the run.
    ///
    @Flag(name: .long, help: "Keep the deployed containers instead of deleting them, for investigating a failure.")
    var keepContainers = false

    ///
    /// The package to run the tests of.
    ///
    @Option(name: .long, help: "The package directory to run the tests of.")
    var packagePath: String = FileManager.default.currentDirectoryPath

    ///
    /// Whether every release is additionally deployed with the High Performance Backend for Files.
    ///
    @Flag(name: .long, help: "Also deploy every release with push notifications, as a second matrix entry.")
    var withPush = false

    ///
    /// The releases to deploy.
    ///
    @Option(name: .long, parsing: .upToNextOption, help: "The server releases to run against. Defaults to the current one and the one before it, derived from what `latest` turns out to be.")
    var tags: [String] = []

    ///
    /// Deploy, test and tear down.
    ///
    /// - Throws: Whatever preflight, deployment or the test process raises.
    ///
    func run() async throws {
        let artifactsDirectory = URL(filePath: artifacts, directoryHint: .isDirectory).appending(path: Self.runIdentifier(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

        let report = await Preflight.checkMachine(allowingUnnotarizedClient: allowDevelopmentClient)
        Console.log(report.description)

        guard report.isSatisfied else {
            throw PreflightError(report: report)
        }

        if noClientReset {
            Console.log("Leaving the desktop client alone, as asked. Suites which need a configured account will fail.")
        } else {
            let didReset = try await ClientReset.perform(backingUpTo: artifactsDirectory.appending(path: "client-configuration-backup", directoryHint: .isDirectory)) { inventory in
                Confirmation.approveReset(of: inventory, isPreApproved: RunEnvironment.isDestructiveAllowedByEnvironment())
            }

            guard didReset else {
                throw RunError.resetDeclined
            }
        }

        let servers = try await ServerMatrix.deploy(tags: tags, includesPush: withPush) { Console.log($0) }

        let result = try await runTests(against: servers.map(\.descriptor), artifactsDirectory: artifactsDirectory)

        if !noClientReset {
            try? await DesktopClient.quit()
        }
        await tearDown(servers)

        let summary = MetricsSummary.render(MetricsSummary.samples(in: artifactsDirectory.appending(path: "attachments", directoryHint: .isDirectory)))
        let summaryURL = artifactsDirectory.appending(path: "metrics.md", directoryHint: .notDirectory)
        try Data(summary.utf8).write(to: summaryURL, options: .atomic)

        Console.log()
        Console.log(summary)
        Console.log()
        Console.log("Artifacts: \(artifactsDirectory.path(percentEncoded: false))")

        guard result.isSuccess else {
            throw RunError.testsFailed(exitCode: result.exitCode)
        }
    }

    ///
    /// Delete the deployed containers, unless the run was asked to keep them.
    ///
    /// - Parameters:
    ///     - servers: The servers to tear down.
    ///
    private func tearDown(_ servers: [ManagedServer]) async {
        guard !keepContainers else {
            Console.log("Keeping \(servers.count) container(s) as requested.")

            return
        }

        for server in servers {
            do {
                try await server.delete()
            } catch {
                // A container which outlives its run is a leak somebody has to clean up by hand, so it is said out loud rather than swallowed.
                Console.log("Failed to delete the container of \(server.descriptor.description): \(error)")
            }
        }
    }

    ///
    /// Run the test process against the deployed servers.
    ///
    /// - Parameters:
    ///     - servers: The servers to hand to the test process.
    ///     - artifactsDirectory: Where the test process writes its artifacts.
    ///
    /// - Returns: The outcome of the test process.
    ///
    /// - Throws: Whatever encoding the matrix or launching the test process raises.
    ///
    private func runTests(against servers: [ServerUnderTest], artifactsDirectory: URL) async throws -> ProcessResult {
        let encoder = JSONEncoder()
        let matrix = try String(decoding: encoder.encode(servers), as: UTF8.self)

        // Swift Testing refuses an attachments path which does not exist yet, so the directory is created rather than left to the test process.
        let attachmentsDirectory = artifactsDirectory.appending(path: "attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        var arguments = [
            "test",
            "--package-path", packagePath,
            "--no-parallel",
            "--xunit-output", artifactsDirectory.appending(path: "results.xml", directoryHint: .notDirectory).path(percentEncoded: false),
            "--attachments-path", attachmentsDirectory.path(percentEncoded: false),
        ]

        if let filter {
            arguments += ["--filter", filter]
        } else {
            arguments += ["--filter", "FileProviderTests"]
        }

        var environment = [
            RunEnvironment.allowDestructiveVariableName: "1",
            RunEnvironment.artifactsDirectoryVariableName: artifactsDirectory.path(percentEncoded: false),
            RunEnvironment.matrixVariableName: matrix,
        ]

        if allowDevelopmentClient {
            environment[RunEnvironment.allowUnnotarizedClientVariableName] = "1"
        }

        Console.log()
        Console.log("Running the tests against \(servers.map(\.description).joined(separator: ", "))...")

        return try await ProcessRunner.runStreamingOutput(URL(filePath: "/usr/bin/swift"), arguments: arguments, environment: environment)
    }

    ///
    /// A name for this run which sorts chronologically.
    ///
    /// - Returns: The name.
    ///
    private static func runIdentifier() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        return formatter.string(from: Date())
    }
}
