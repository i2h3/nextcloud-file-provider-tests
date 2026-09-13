// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Finds the directory macOS mounts a client account's File Provider domain at.
///
/// The naming scheme of those directories is the system's business and has changed before, so nothing here guesses one. Instead the contents of ``ClientPaths/cloudStorage`` are compared before and after an account is created, which identifies the new domain no matter what it ends up being called, and the result is cross-checked against the defaults the extension writes into its application group.
///
public enum DomainLocator {
    ///
    /// The domain directories currently present.
    ///
    /// Reading this directory enumerates it, but it is the mount point of every provider rather than a container of the provider under test, so nothing about the client's own state is disturbed by it.
    ///
    /// - Returns: One URL per mounted domain directory, sorted by name.
    ///
    public static func mountedDomains() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ClientPaths.cloudStorage.path(percentEncoded: false))) ?? []

        return names
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { ClientPaths.cloudStorage.appending(path: $0, directoryHint: .isDirectory) }
    }

    ///
    /// Wait for a domain which was not there before to appear and become readable.
    ///
    /// A domain directory exists slightly before the extension serves it, so appearance alone is not enough: the root is read once to confirm the domain answers. That first read is the one enumeration a clean room performs on the test's behalf, and it is recorded in the ledger like any other.
    ///
    /// - Parameters:
    ///     - known: The domain directories which existed before the account was created.
    ///     - ledger: The ledger to record the confirming enumeration in.
    ///     - timeout: How long to wait for the domain.
    ///
    /// - Returns: The directory of the newly appeared domain.
    ///
    /// - Throws: ``WaitTimeoutError`` if no new domain appears in time.
    ///
    public static func waitForNewDomain(besides known: [URL], ledger: EnumerationLedger, timeout: Duration) async throws -> URL {
        let domain = try await waitForNewDomainDirectory(besides: known, timeout: timeout)
        try await confirmReadable(domain, ledger: ledger, timeout: timeout)

        return domain
    }

    ///
    /// Wait for a domain directory which was not there before to appear.
    ///
    /// Only `lstat` is used, which answers immediately whatever state the provider is in. Enumerating the directory is a separate, deliberate step — see ``confirmReadable(_:ledger:timeout:)`` — because that call can take many seconds and must not be repeated in a polling loop.
    ///
    /// - Parameters:
    ///     - known: The domain directories which existed before the account was created.
    ///     - timeout: How long to wait for the directory.
    ///
    /// - Returns: The directory of the newly appeared domain.
    ///
    /// - Throws: ``WaitTimeoutError`` if no new directory appears in time.
    ///
    public static func waitForNewDomainDirectory(besides known: [URL], timeout: Duration) async throws -> URL {
        let knownPaths = Set(known.map { $0.standardizedFileURL.path(percentEncoded: false) })

        return try await Waiter.waitForValue("a new File Provider domain appears in \(ClientPaths.cloudStorage.path(percentEncoded: false))", timeout: timeout) {
            mountedDomains().first { !knownPaths.contains($0.standardizedFileURL.path(percentEncoded: false)) }
        }
    }

    ///
    /// Enumerate a domain once, to confirm that its provider answers.
    ///
    /// Two things make this call slow. A domain directory exists a little before its extension serves it, and — the first time a process reads any domain — macOS asks the person at the machine whether this application may access files managed by another one. That dialog blocks the call for as long as it goes unanswered, which is why an unattended machine has to have the consent granted beforehand; see the machine setup section of the README.
    ///
    /// It is therefore done exactly once, with a deadline of its own, rather than in a polling loop: repeating it only queues more work behind a call which is already waiting, and the wait would never finish.
    ///
    /// - Parameters:
    ///     - domain: The domain to confirm.
    ///     - ledger: The ledger to record this enumeration in.
    ///     - timeout: How long to give the provider.
    ///     - attempts: How often to try before giving up, since a refused consent can be granted between attempts.
    ///     - pauseBetweenAttempts: How long to wait between attempts, which is also the time somebody has to answer the dialog.
    ///
    /// - Throws: ``WaitTimeoutError`` if the provider does not answer in time, or ``DomainNotReadableError`` if every attempt is refused.
    ///
    public static func confirmReadable(_ domain: URL, ledger: EnumerationLedger, timeout: Duration, attempts: Int = 3, pauseBetweenAttempts: Duration = .seconds(20)) async throws {
        var lastRefusal: String?

        for attempt in 1 ... max(1, attempts) {
            let failure = try await Deadline.runBlocking(within: timeout) {
                do {
                    _ = try LocalDirectory.children(of: domain, ledger: ledger)

                    return String?.none
                } catch {
                    return String(describing: error)
                }
            }

            guard let failure else {
                throw WaitTimeoutError(expectation: "the provider of the domain at \(domain.path(percentEncoded: false)) answers its first enumeration", timeout: timeout)
            }

            guard let refusal = failure else {
                return
            }

            lastRefusal = refusal

            // A refusal is not necessarily final. macOS suppresses consent dialogs which come too fast after one another and answers those requests with a refusal instead of asking, so the same read can succeed a little later, once somebody has been given the chance to allow it.
            if attempt < attempts {
                try await Task.sleep(for: pauseBetweenAttempts)
            }
        }

        throw DomainNotReadableError(domain: domain, reason: lastRefusal ?? "unknown")
    }

    ///
    /// Wait for a domain directory to disappear again.
    ///
    /// - Parameters:
    ///     - domain: The domain directory which is expected to go away.
    ///     - timeout: How long to wait for it.
    ///
    /// - Throws: ``WaitTimeoutError`` if the directory is still there afterwards.
    ///
    public static func waitForRemoval(of domain: URL, timeout: Duration) async throws {
        try await Waiter.waitUntil("the domain at \(domain.path(percentEncoded: false)) is gone", timeout: timeout) {
            try !LocalDirectory.exists(domain)
        }
    }
}
