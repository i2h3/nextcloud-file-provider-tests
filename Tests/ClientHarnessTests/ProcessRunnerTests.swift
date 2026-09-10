// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``ProcessRunner``.
///
/// Every interaction with the desktop client goes through this type, so a run which never returns stalls the whole suite with nothing to show for it. That is not hypothetical: waiting for a child through `waitUntilExit` did exactly that, which is why these tests exist and why they carry a time limit.
///
@Suite("Process runner", .timeLimit(.minutes(1)))
struct ProcessRunnerTests {
    @Test
    func `A command which succeeds is reported with its output.`() async throws {
        let result = try await ProcessRunner.run(URL(filePath: "/bin/echo"), arguments: ["hello"])

        #expect(result.isSuccess)
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "hello")
        #expect(result.standardError.isEmpty)
    }

    @Test
    func `A command which fails is reported rather than raised.`() async throws {
        let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/false"), arguments: [])

        #expect(!result.isSuccess)
        #expect(result.exitCode == 1)
    }

    @Test
    func `Requiring success turns a failure into an error.`() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            try await ProcessRunner.runSuccessfully(URL(filePath: "/usr/bin/false"), arguments: [])
        }
    }

    @Test
    func `A tool which does not exist is reported as unlaunchable.`() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            try await ProcessRunner.run(URL(filePath: "/usr/bin/there-is-no-such-tool"), arguments: [])
        }
    }

    @Test
    func `Standard error is collected separately from standard output.`() async throws {
        let result = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo out; echo err 1>&2"])

        #expect(result.standardOutput == "out")
        #expect(result.standardError == "err")
    }

    @Test
    func `Output larger than a pipe buffer does not deadlock.`() async throws {
        let result = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "for i in $(seq 1 20000); do echo 'a line of output which is long enough to matter'; done"])

        #expect(result.isSuccess)
        #expect(result.standardOutput.count > 512 * 1024)
    }

    @Test
    func `Many commands in sequence all return.`() async throws {
        for index in 0 ..< 25 {
            let result = try await ProcessRunner.run(URL(filePath: "/bin/echo"), arguments: ["\(index)"])

            #expect(result.standardOutput == "\(index)")
        }
    }

    @Test
    func `Added environment variables reach the command.`() async throws {
        let result = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo $FPT_PROBE"], environment: ["FPT_PROBE": "visible"])

        #expect(result.standardOutput == "visible")
    }
}
