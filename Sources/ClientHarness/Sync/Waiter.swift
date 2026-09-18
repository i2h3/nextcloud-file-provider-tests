// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Synchronization

///
/// Waits for a condition to come true, with a deadline.
///
/// Synchronisation is asynchronous and the test process cannot observe the File Provider extension's schedule — `NSFileProviderManager` is reserved for the provider's own app, so there is no `waitForChanges` to call. Every wait in the suite therefore goes through this one primitive instead of through a sleep, so that a fast machine is fast, a slow one still passes, and a failure always says what was awaited.
///
public enum Waiter {
    ///
    /// The interval the first polls are spaced by.
    ///
    public static let initialPollInterval = Duration.milliseconds(100)

    ///
    /// The interval polls settle at once a condition takes longer.
    ///
    /// Polling backs off rather than staying tight because every poll of a File Provider domain is itself work for the extension under test.
    ///
    public static let maximumPollInterval = Duration.seconds(1)

    ///
    /// How long a single evaluation of a condition may take before it is abandoned.
    ///
    /// Anything which reads a File Provider domain can block for as long as the provider stays silent, so an attempt is given a deadline of its own and the wait moves on when it is exceeded. See ``Deadline``.
    ///
    public static let attemptTimeout = Duration.seconds(20)

    ///
    /// Wait until a condition which blocks in the file system holds.
    ///
    /// Use this rather than ``waitUntil(_:timeout:attemptTimeout:condition:)`` for anything which reads a File Provider domain — `lstat`, a directory listing, a resource value. Those calls block in the kernel for as long as the provider stays silent, and running enough of them on the cooperative thread pool starves it, at which point the deadline that was supposed to rescue the wait cannot run either.
    ///
    /// - Parameters:
    ///     - expectation: What is awaited, phrased so that it reads as a sentence after "waiting until".
    ///     - timeout: How long to wait before giving up.
    ///     - attemptTimeout: How long a single evaluation of the condition may take before it is abandoned. Defaults to ``attemptTimeout``.
    ///     - diagnosis: What the last look found, evaluated once if the wait runs out. A condition which swallows its own errors to keep polling knows why it is still false, and this is where it says so — see ``WaitTimeoutError/diagnosis``.
    ///     - condition: The condition to evaluate repeatedly, on a thread of its own.
    ///
    /// - Throws: ``WaitTimeoutError`` if the condition does not hold in time, or whatever the condition itself throws.
    ///
    public static func waitUntilBlocking(_ expectation: String, timeout: Duration, attemptTimeout: Duration = attemptTimeout, diagnosis: (@Sendable () -> String?)? = nil, condition: @escaping @Sendable () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        var pollInterval = initialPollInterval

        while true {
            // The difference from ``waitUntil`` is the whole point of this being separate: the condition runs on a thread of its own rather than on the cooperative pool. A condition which reads a File Provider domain blocks in the kernel, and enough of those on the pool starve it — which is the failure ``Deadline/runBlocking(within:work:)`` exists for.
            let attempt = try await Deadline.runBlocking(within: attemptTimeout, work: condition)

            if attempt == true {
                return
            }

            guard ContinuousClock.now < deadline else {
                throw WaitTimeoutError(expectation: expectation, timeout: timeout, diagnosis: diagnosis?())
            }

            try await Task.sleep(for: pollInterval)
            pollInterval = min(pollInterval * 2, maximumPollInterval)
        }
    }

    ///
    /// Wait until a condition holds.
    ///
    /// - Parameters:
    ///     - expectation: What is awaited, phrased so that it reads as a sentence after "waiting until".
    ///     - timeout: How long to wait before giving up.
    ///     - attemptTimeout: How long a single evaluation of the condition may take before it is abandoned. Defaults to ``attemptTimeout``.
    ///     - diagnosis: What the last look found, evaluated once if the wait runs out. See ``WaitTimeoutError/diagnosis``.
    ///     - condition: The condition to evaluate repeatedly.
    ///
    /// - Throws: ``WaitTimeoutError`` if the condition does not hold in time, or whatever the condition itself throws.
    ///
    public static func waitUntil(_ expectation: String, timeout: Duration, attemptTimeout: Duration = attemptTimeout, diagnosis: (@Sendable () -> String?)? = nil, condition: @escaping @Sendable () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        var pollInterval = initialPollInterval

        while true {
            // Each attempt gets a deadline of its own. A condition which reads a File Provider domain can block in the kernel and never return, and without this the overall timeout would never be reached, because it is only ever examined between attempts.
            let attempt = try await Deadline.run(within: attemptTimeout, work: condition)

            if attempt == true {
                return
            }

            guard ContinuousClock.now < deadline else {
                throw WaitTimeoutError(expectation: expectation, timeout: timeout, diagnosis: diagnosis?())
            }

            try await Task.sleep(for: pollInterval)
            pollInterval = min(pollInterval * 2, maximumPollInterval)
        }
    }

    ///
    /// Wait until a condition holds, without giving the condition a deadline of its own.
    ///
    /// The difference to ``waitUntil(_:timeout:attemptTimeout:condition:)`` is what the condition is allowed to do. That one guards against work which never returns, which costs it a thread per abandoned attempt and requires the condition to be sendable. This one is for work which cannot wedge a thread — anything which talks to a server over the network, where the request carries its own timeout — and it accepts a plain closure, which is what makes it usable with types that are not sendable, such as Rainmaker's `Server`.
    ///
    /// - Parameters:
    ///     - expectation: What is awaited, phrased so that it reads as a sentence after "waiting until".
    ///     - timeout: How long to wait before giving up.
    ///     - diagnosis: What the last look found, evaluated once if the wait runs out. See ``WaitTimeoutError/diagnosis``.
    ///     - condition: The condition to evaluate repeatedly.
    ///
    /// - Throws: ``WaitTimeoutError`` if the condition does not hold in time, or whatever the condition itself throws.
    ///
    public static func poll(_ expectation: String, timeout: Duration, diagnosis: (() -> String?)? = nil, condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        var pollInterval = initialPollInterval

        while true {
            if try await condition() {
                return
            }

            guard ContinuousClock.now < deadline else {
                throw WaitTimeoutError(expectation: expectation, timeout: timeout, diagnosis: diagnosis?())
            }

            try await Task.sleep(for: pollInterval)
            pollInterval = min(pollInterval * 2, maximumPollInterval)
        }
    }

    ///
    /// Wait until a value is available, then return it.
    ///
    /// - Parameters:
    ///     - expectation: What is awaited, phrased so that it reads as a sentence after "waiting until".
    ///     - timeout: How long to wait before giving up.
    ///     - production: The value to produce, or `nil` while it is not available yet.
    ///
    /// - Returns: The produced value.
    ///
    /// - Throws: ``WaitTimeoutError`` if no value becomes available in time, or whatever the production itself throws.
    ///
    public static func waitForValue<Value: Sendable>(_ expectation: String, timeout: Duration, production: @escaping @Sendable () async throws -> Value?) async throws -> Value {
        let produced = Mutex<Value?>(nil)

        try await waitUntil(expectation, timeout: timeout) {
            guard let value = try await production() else {
                return false
            }

            produced.withLock { $0 = value }

            return true
        }

        guard let value = produced.withLock({ $0 }) else {
            throw WaitTimeoutError(expectation: expectation, timeout: timeout)
        }

        return value
    }
}
