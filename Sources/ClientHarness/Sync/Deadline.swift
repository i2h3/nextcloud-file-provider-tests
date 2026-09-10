// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Runs work with a deadline it cannot overrun, even when the work refuses to return.
///
/// This exists because of one hard-won fact: reading a File Provider domain can block indefinitely. An `open` or `readdir` below `~/Library/CloudStorage` waits for the provider to answer, and it also waits for the person at the machine when macOS decides to ask whether this application may access files managed by another one. A provider which is starting, wedged or unauthenticated never answers, and neither does a dialog nobody is there to click. Such a call is not cancellable — `Task.cancel()` does not interrupt a blocking system call — so the only honest thing a harness can do is stop waiting for it, report that, and carry on.
///
/// The abandoned work is left running. That is deliberate: leaking a blocked thread is a far smaller problem than a test run which hangs until somebody notices it.
///
public enum Deadline {
    ///
    /// Run work, giving up on it after a while.
    ///
    /// - Parameters:
    ///     - duration: How long to wait for the work.
    ///     - work: The work to run.
    ///
    /// - Returns: What the work produced, or `nil` if it did not produce anything in time.
    ///
    /// - Throws: Whatever the work throws, if it throws before the deadline.
    ///
    public static func run<Value: Sendable>(within duration: Duration, work: @escaping @Sendable () async throws -> Value) async throws -> Value? {
        let (outcomes, outcome) = AsyncThrowingStream<Value?, any Error>.makeStream()

        // The racer is detached: the point of this type is that the work outlives the wait when it will not return, so it must not be a child of the task which gave up on it.
        Task.detached {
            do {
                try await outcome.yield(work())
                outcome.finish()
            } catch {
                outcome.finish(throwing: error)
            }
        }

        scheduleGivingUp(after: duration, on: outcome)

        for try await first in outcomes {
            return first
        }

        return nil
    }

    ///
    /// Run blocking work on a thread of its own, giving up on it after a while.
    ///
    /// Everything which touches a File Provider domain goes through here rather than through ``run(within:work:)``. The reason is the cooperative thread pool: it has about as many threads as the machine has cores, a blocking system call occupies one of them for as long as it blocks, and a handful of abandoned calls therefore starve the pool until nothing else can run — including the timer which is supposed to give up on them. The run then hangs anyway, which is precisely what the deadline was introduced to prevent.
    ///
    /// Dispatch's global queue has no such problem: it grows when its workers block.
    ///
    /// - Parameters:
    ///     - duration: How long to wait for the work.
    ///     - work: The blocking work to run.
    ///
    /// - Returns: What the work produced, or `nil` if it did not produce anything in time.
    ///
    /// - Throws: Whatever the work throws, if it throws before the deadline.
    ///
    public static func runBlocking<Value: Sendable>(within duration: Duration, work: @escaping @Sendable () throws -> Value) async throws -> Value? {
        let (outcomes, outcome) = AsyncThrowingStream<Value?, any Error>.makeStream()

        DispatchQueue.global().async {
            do {
                try outcome.yield(work())
                outcome.finish()
            } catch {
                outcome.finish(throwing: error)
            }
        }

        scheduleGivingUp(after: duration, on: outcome)

        for try await first in outcomes {
            return first
        }

        return nil
    }

    ///
    /// Arrange for a wait to end even if the work never does.
    ///
    /// The timer runs on a dispatch queue rather than as a sleeping task, for the same reason the blocking work does: a starved cooperative pool would never get around to it.
    ///
    /// - Parameters:
    ///     - duration: How long to wait before giving up.
    ///     - outcome: The stream to end.
    ///
    private static func scheduleGivingUp<Value: Sendable>(after duration: Duration, on outcome: AsyncThrowingStream<Value?, any Error>.Continuation) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            outcome.yield(nil)
            outcome.finish()
        }
    }
}
