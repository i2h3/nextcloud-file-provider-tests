// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Synchronization
import Testing

///
/// Tests for what a ``Waiter`` says when it runs out.
///
/// Most conditions in this suite swallow their own errors, because a file system answers "not yet" and "never" with the same absence and a wait which propagated the first would never reach the second. The cost is that a timeout reports what did not appear and stays silent about what was there instead — which, in the run this was written for, was the difference between three blank reports and one sentence about the client.
///
@Suite("Waiter diagnosis")
struct WaiterDiagnosisTests {
    @Test
    func `A timeout without a diagnosis reads as it always did.`() {
        let error = WaitTimeoutError(expectation: "\"before.bin\" reaches the client", timeout: .seconds(180))

        #expect(error.description == "Timed out after 180.0 seconds waiting until \"before.bin\" reaches the client.")
    }

    @Test
    func `A timeout with a diagnosis says what was found instead.`() {
        let error = WaitTimeoutError(
            expectation: "\"before-Sibling.bin\" reaches the client",
            timeout: .seconds(180),
            diagnosis: "the domain's root holding before-sibling.bin"
        )

        #expect(error.description.contains("before-sibling.bin"))
        #expect(error.description.hasSuffix("The last look found the domain's root holding before-sibling.bin."))
    }

    ///
    /// The diagnosis is evaluated once, at the end, rather than on every poll — a listing of a File Provider domain is work for the extension under test, and a wait which performed one per second for three minutes would be measuring itself.
    ///
    @Test
    func `A diagnosis is asked only when the wait runs out.`() async throws {
        let asked = Mutex(0)

        try await Waiter.waitUntilBlocking("a condition which holds at once", timeout: .seconds(1), diagnosis: { asked.withLock { $0 += 1 }; return "nothing" }) {
            true
        }

        #expect(asked.withLock { $0 } == 0)

        await #expect(throws: WaitTimeoutError.self) {
            try await Waiter.waitUntilBlocking("a condition which never holds", timeout: .milliseconds(250), diagnosis: { asked.withLock { $0 += 1 }; return "nothing" }) {
                false
            }
        }

        #expect(asked.withLock { $0 } == 1)
    }
}
