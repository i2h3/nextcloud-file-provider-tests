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
    var artifacts: String = "Artifacts"

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
    /// Whether the test process is asked to record its event stream.
    ///
    @Flag(name: .long, help: "Do not ask the test process for its event stream. Only needed if a toolchain stops accepting the option, which is not a documented one.")
    var noEventStream = false

    ///
    /// Whether a failed run drafts bug reports for what went wrong.
    ///
    @Flag(name: .long, help: "Do not draft bug reports for the failures of this run.")
    var noReport = false

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

        // Stamped, because a run takes hours and a terminal keeps several of them. Without this there is no way to tell from a scrollback which run is on the screen, when it started, or whether it has anything left to do — which is the question somebody has when they come back to it, and the one the output could not answer.
        let began = Date()

        Console.milestone("Run \(artifactsDirectory.lastPathComponent) started.")

        let report = await Preflight.checkMachine(allowingUnnotarizedClient: allowDevelopmentClient)
        Console.log(report.description)

        // Written before the servers exist, so that a run which never gets that far still records what it was and what it found. It is rewritten once they do.
        var manifest = RunManifest(runIdentifier: artifactsDirectory.lastPathComponent, command: describeCommand(), preflight: report)
        try? manifest.write(into: artifactsDirectory)

        guard report.isSatisfied else {
            throw PreflightError(report: report)
        }

        if noClientReset {
            // The configuration is copied aside even so, because this flag does not protect it and reads as though it does.
            //
            // What it skips is the machine-level reset: the confirmation, the domains, the keychain. It does not stop a clean room wiping the configuration directory, which every room does on its way in — so a run started with this flag and a filter which happens to include a suite that builds rooms destroys the configuration with neither a confirmation nor a backup. The flag is meant for the server-only suites and nothing enforces that it is used for them. A copy costs a directory and removes the sharp edge.
            Console.log("Leaving the desktop client's machine-level reset alone, as asked. Its configuration is still copied aside first: any suite which builds a clean room replaces it regardless of this flag.")

            try? ClientReset.backUpConfiguration(to: artifactsDirectory.appending(path: "client-configuration-backup", directoryHint: .isDirectory))
        } else {
            let didReset = try await ClientReset.perform(backingUpTo: artifactsDirectory.appending(path: "client-configuration-backup", directoryHint: .isDirectory)) { inventory in
                Confirmation.approveReset(of: inventory, isPreApproved: RunEnvironment.isDestructiveAllowedByEnvironment())
            }

            guard didReset else {
                throw RunError.resetDeclined
            }
        }

        let servers = try await ServerMatrix.deploy(tags: tags, includesPush: withPush) { Console.milestone($0) }

        // Recorded where `teardown` looks, which until now only `prepare` did.
        //
        // A run tears its own containers down at the end, so the record is redundant on the path where nothing goes wrong. On every other path it is the only way back: a run stopped with ctrl-C, killed, or ended by a crash leaves four Nextcloud containers and their sidecars running, and `swift run tests teardown` answered "No prepared session was found" — while the identifiers sat in this run's own `run.json`, written one line below. The cleanup existed and the command that performs it could not see it.
        let session = SessionDirectory(artifacts: artifacts)
        try? session.write(servers.map(\.descriptor))

        manifest.servers = servers.map { RunManifestServer($0.descriptor) }
        try? manifest.write(into: artifactsDirectory)

        let result = try await runTests(against: servers.map(\.descriptor), artifactsDirectory: artifactsDirectory)

        Console.log()
        Console.milestone("Tests finished. Tearing down...")

        if !noClientReset {
            try? await DesktopClient.quit()
        }

        // Debug logging belongs to a run, and a run is over. Clearing it only at the start of the next one leaves it on in between, which quietly fills the disk of somebody who has stopped running tests.
        //
        // Cleared whichever way the flag went, because a clean room turns it on whichever way the flag went. It used to sit inside the branch above, so a run which asked not to reset the client switched the extension's debug logging on once per room and never off — the one state this flag could actually have protected, left set by the code meant to protect it.
        await ClientLogging.disableDebugLogging()
        await tearDown(servers, session: session)

        manifest.finishedAt = Date()
        try? manifest.write(into: artifactsDirectory)

        let summary = MetricsSummary.render(MetricsSummary.samples(in: artifactsDirectory.appending(path: "attachments", directoryHint: .isDirectory)))
        let summaryURL = artifactsDirectory.appending(path: "metrics.md", directoryHint: .notDirectory)
        try Data(summary.utf8).write(to: summaryURL, options: .atomic)

        Console.log()
        Console.log(summary)
        Console.log()
        Console.milestone("""
        Run \(artifactsDirectory.lastPathComponent) finished, having taken \(Console.spoken(Date().timeIntervalSince(began))) since \(Console.timestamp(began)).
        """)
        Console.log("Artifacts: \(artifactsDirectory.path(percentEncoded: false))")

        writeIndex(in: artifactsDirectory)

        guard result.isSuccess else {
            draftReports(in: artifactsDirectory)

            throw RunError.testsFailed(exitCode: result.exitCode)
        }

        // A test process which matched nothing exits successfully and says so only in a warning, so a mistyped filter otherwise reads as a clean run of the whole suite.
        guard JUnitReader.ranAnyTests(in: artifactsDirectory.appending(path: JUnitReader.fileName, directoryHint: .notDirectory)) else {
            throw RunError.noTestsRun(filter: filter)
        }
    }

    ///
    /// Write the page which says what this run did.
    ///
    /// Written for every run rather than only for a failing one, and before the failure is thrown, because a run which passed is exactly as worth reading as one which did not — the measurements, the declined clauses and the cells which were never judged are the parts nobody sees in a terminal.
    ///
    /// A failure here is reported and then ignored, for the same reason a reporting failure is: a run's result must never be lost to a problem with describing it.
    ///
    /// - Parameters:
    ///     - artifactsDirectory: The directory the run wrote to.
    ///
    private func writeIndex(in artifactsDirectory: URL) {
        do {
            let url = try RunIndex.write(for: RunEvidence.gather(from: artifactsDirectory))

            Console.log("Overview:  \(url.path(percentEncoded: false))")
        } catch {
            Console.log("Could not write the run overview: \(error)")
        }
    }

    ///
    /// Draft a bug report for everything which went wrong, if anything did.
    ///
    /// Done without being asked, for the same reason the measurements are: the drafts which matter are the ones written on the first run rather than the third, and by the third nobody remembers what the first one ruled out. A failure here is reported and then ignored — a run's result is the thing being reported on, and must never be lost to a problem with the reporting.
    ///
    /// - Parameters:
    ///     - artifactsDirectory: The directory the run wrote to.
    ///
    private func draftReports(in artifactsDirectory: URL) {
        guard !noReport else {
            return
        }

        do {
            let written = try BugReportWriter.write(for: RunEvidence.gather(from: artifactsDirectory))

            guard !written.isEmpty else {
                return
            }

            Console.log()
            Console.describe(written)
        } catch {
            Console.log("Could not draft a bug report: \(error)")
        }
    }

    ///
    /// Delete the deployed containers, unless the run was asked to keep them.
    ///
    /// - Parameters:
    ///     - servers: The servers to tear down.
    ///     - session: The record of what was deployed, cleared only once nothing is left in it.
    ///
    private func tearDown(_ servers: [ManagedServer], session: SessionDirectory) async {
        guard !keepContainers else {
            Console.log("Keeping \(servers.count) container(s) as requested. `swift run tests teardown` removes them.")

            return
        }

        var removed = 0

        for server in servers {
            do {
                try await server.delete()
                removed += 1
            } catch {
                // A container which outlives its run is a leak somebody has to clean up by hand, so it is said out loud rather than swallowed.
                Console.log("Failed to delete the container of \(server.descriptor.description): \(error)")
            }
        }

        guard removed == servers.count else {
            Console.log("\(servers.count - removed) container(s) are still running and are still recorded. `swift run tests teardown` can be run again.")

            return
        }

        session.clear()
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

        // The xUnit report records one entry per test function, so a test which failed for one server and passed for another appears as a single failure with no way to tell which. The event stream is the only artifact which distinguishes them, and it carries the moment of each failure, which is what ties it to the clean room it happened in. The option is not a documented one, hence the flag to do without it.
        if !noEventStream {
            arguments += [
                "--event-stream-output-path", artifactsDirectory.appending(path: "events.jsonl", directoryHint: .notDirectory).path(percentEncoded: false),
                "--event-stream-version", "0",
            ]
        }

        var environment = [
            RunEnvironment.allowDestructiveVariableName: "1",
            RunEnvironment.artifactsDirectoryVariableName: artifactsDirectory.path(percentEncoded: false),
            RunEnvironment.matrixVariableName: matrix,
        ]

        if allowDevelopmentClient {
            environment[RunEnvironment.allowUnnotarizedClientVariableName] = "1"
        }

        // The test process is given an environment built here rather than inheriting this one, which is what keeps a run reproducible — but it means anything a person sets on the command line reaches nothing unless it is named. These two are settings of the run rather than of the machine, so they are forwarded when present.
        for name in [RunEnvironment.repetitionsVariableName, RunEnvironment.timeoutScaleVariableName] {
            guard let value = ProcessInfo.processInfo.environment[name] else {
                continue
            }

            environment[name] = value
        }

        Console.log()
        Console.milestone("Running the tests against \(servers.map(\.description).joined(separator: ", "))...")

        return try await ProcessRunner.runStreamingOutput(URL(filePath: "/usr/bin/swift"), arguments: arguments, environment: environment)
    }

    ///
    /// How this run was asked for, for the record.
    ///
    /// - Returns: The options which change what a run does, as strings.
    ///
    private func describeCommand() -> [String: String] {
        [
            "allowDevelopmentClient": String(allowDevelopmentClient),
            "filter": filter ?? "",
            "keepContainers": String(keepContainers),
            "noClientReset": String(noClientReset),
            "noEventStream": String(noEventStream),
            "tags": tags.joined(separator: ","),
            "withPush": String(withPush),
        ]
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
