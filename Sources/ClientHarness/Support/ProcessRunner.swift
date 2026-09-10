// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Runs command line tools and collects their output.
///
/// Controlling the desktop client, inspecting code signatures and reading the unified log all happen through command line tools, so this is the single place which knows how to do that safely. Both output streams are drained concurrently, because a command which writes more than a pipe buffer to one of them would otherwise deadlock waiting for a reader which is itself waiting for the process to exit.
///
public enum ProcessRunner {
    ///
    /// Run a command and wait for it to finish.
    ///
    /// - Parameters:
    ///     - executable: The tool to run.
    ///     - arguments: The arguments to pass to it.
    ///     - environment: Environment variables to add to the ones of the current process. Defaults to none.
    ///
    /// - Returns: The exit status and the collected output.
    ///
    /// - Throws: ``ProcessRunnerError/notLaunchable(executable:reason:)`` if the tool cannot be started.
    ///
    @discardableResult
    public static func run(_ executable: URL, arguments: [String], environment: [String: String] = [:]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let standardErrorPipe = Pipe()
        let standardOutputPipe = Pipe()
        process.standardError = standardErrorPipe
        process.standardOutput = standardOutputPipe

        async let standardError = drain(standardErrorPipe)
        async let standardOutput = drain(standardOutputPipe)

        // The exit status is awaited through the termination handler rather than through `waitUntilExit`, which runs a run loop on the calling thread and has been observed to miss the notification and block forever when it is called from a task rather than from the main thread.
        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminated in
                continuation.resume(returning: terminated.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil

                // Nothing will ever write to the pipes now, and a reader waiting for an end which never comes would keep the enclosing task alive forever. Closing the write ends by hand gives both readers their end of file.
                try? standardErrorPipe.fileHandleForWriting.close()
                try? standardOutputPipe.fileHandleForWriting.close()

                continuation.resume(throwing: ProcessRunnerError.notLaunchable(executable: executable, reason: String(describing: error)))
            }
        }

        return await ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError)
    }

    ///
    /// Run a command and let its output through to the terminal instead of collecting it.
    ///
    /// Some commands are themselves long-running and worth watching — the test process above all. Collecting their output would hide everything until they finish and then dump it at once, and on a failure it would be lost entirely unless the caller remembered to print it.
    ///
    /// - Parameters:
    ///     - executable: The tool to run.
    ///     - arguments: The arguments to pass to it.
    ///     - environment: Environment variables to add to the ones of the current process. Defaults to none.
    ///
    /// - Returns: The exit status. Both output streams are empty, because they went to the terminal.
    ///
    /// - Throws: ``ProcessRunnerError/notLaunchable(executable:reason:)`` if the tool cannot be started.
    ///
    @discardableResult
    public static func runStreamingOutput(_ executable: URL, arguments: [String], environment: [String: String] = [:]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardError = FileHandle.standardError
        process.standardOutput = FileHandle.standardOutput

        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminated in
                continuation.resume(returning: terminated.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: ProcessRunnerError.notLaunchable(executable: executable, reason: String(describing: error)))
            }
        }

        return ProcessResult(exitCode: exitCode, standardOutput: "", standardError: "")
    }

    ///
    /// Run a command and require it to succeed.
    ///
    /// - Parameters:
    ///     - executable: The tool to run.
    ///     - arguments: The arguments to pass to it.
    ///     - environment: Environment variables to add to the ones of the current process. Defaults to none.
    ///
    /// - Returns: The exit status and the collected output.
    ///
    /// - Throws: ``ProcessRunnerError`` if the tool cannot be started or reports failure.
    ///
    @discardableResult
    public static func runSuccessfully(_ executable: URL, arguments: [String], environment: [String: String] = [:]) async throws -> ProcessResult {
        let result = try await run(executable, arguments: arguments, environment: environment)

        guard result.isSuccess else {
            throw ProcessRunnerError.failed(executable: executable, arguments: arguments, result: result)
        }

        return result
    }

    ///
    /// Read one output stream to its end.
    ///
    /// - Parameters:
    ///     - pipe: The pipe to read from.
    ///
    /// - Returns: The decoded output, trimmed of surrounding whitespace.
    ///
    private static func drain(_ pipe: Pipe) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
