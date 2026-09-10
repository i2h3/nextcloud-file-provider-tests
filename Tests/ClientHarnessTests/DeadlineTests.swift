// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``Deadline`` and the deadline ``Waiter`` puts on every attempt.
///
/// The behaviour under test is the one which keeps a run from hanging forever: work which never returns has to be abandoned. It is exercised with a blocking system call rather than with a sleep, because a sleeping task is cancellable and a blocked one is not — and the blocked one is the case which matters.
///
@Suite("Deadline", .timeLimit(.minutes(1)))
struct DeadlineTests {
    @Test
    func `Work which finishes in time returns its value.`() async throws {
        let value = try await Deadline.run(within: .seconds(10)) { 42 }

        #expect(value == 42)
    }

    @Test
    func `Work which throws in time propagates its error.`() async throws {
        await #expect(throws: WaitTimeoutError.self) {
            try await Deadline.run(within: .seconds(10)) {
                throw WaitTimeoutError(expectation: "something", timeout: .seconds(1))
            }
        }
    }

    @Test
    func `Work which blocks in a system call is abandoned rather than awaited.`() async throws {
        let started = ContinuousClock.now

        let value: Int? = try await Deadline.run(within: .milliseconds(300)) {
            // A read from a pipe nobody writes to blocks in the kernel and ignores cancellation, which is exactly how a File Provider domain behaves when its provider does not answer.
            let pipe = Pipe()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()

            return 1
        }

        #expect(value == nil)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test
    func `A wait whose condition blocks still reaches its own timeout.`() async throws {
        let started = ContinuousClock.now

        await #expect(throws: WaitTimeoutError.self) {
            try await Waiter.waitUntil("something which never happens", timeout: .milliseconds(100), attemptTimeout: .milliseconds(300)) {
                let pipe = Pipe()
                _ = pipe.fileHandleForReading.readDataToEndOfFile()

                return true
            }
        }

        #expect(ContinuousClock.now - started < .seconds(5), "The wait must not sit through more than one abandoned attempt.")
    }

    @Test
    func `Blocking work on a thread of its own is abandoned without starving the pool.`() async {
        let started = ContinuousClock.now

        // More blocked calls than the cooperative pool has threads. Run through `Deadline.run` these would starve it and the deadlines would never fire, which is the failure this variant exists to avoid.
        await withTaskGroup(of: Int?.self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    try? await Deadline.runBlocking(within: .milliseconds(300)) {
                        let pipe = Pipe()
                        _ = pipe.fileHandleForReading.readDataToEndOfFile()

                        return 1
                    } ?? nil
                }
            }

            for await outcome in group {
                #expect(outcome == nil)
            }
        }

        #expect(ContinuousClock.now - started < .seconds(10), "Every deadline has to fire even while every worker is blocked.")
    }
}
