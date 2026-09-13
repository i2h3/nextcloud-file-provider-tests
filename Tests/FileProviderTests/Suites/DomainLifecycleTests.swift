// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// The File Provider domain exists when it should, is empty when it should be, and goes away again.
///
/// This is the first suite for a reason: everything else assumes that configuring an account through the client's command line options produces a domain which answers, and that a freshly created user starts with nothing in it.
///
@Suite("Domain lifecycle", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(5)))
struct DomainLifecycleTests {
    @Test(arguments: LiveEnvironment.servers)
    func `Configuring an account produces a File Provider domain.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "DomainLifecycle.domainAppears") { room in
            try #expect(LocalDirectory.exists(room.domain))
            #expect(room.domain.path(percentEncoded: false).hasPrefix(ClientPaths.cloudStorage.path(percentEncoded: false)))
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A freshly created user starts with an empty files root.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "DomainLifecycle.startsEmpty") { room in
            let remote = try await RemoteListing.children(of: "/", on: room.server)

            guard remote.isEmpty else {
                try await room.collectDiagnostics(reason: "The server created the user with demo content: \(remote.map(\.name).joined(separator: ", "))")
                Issue.record("A new user should start with an empty files root, but the server reports: \(remote.map(\.name).joined(separator: ", ")). Check that the skeleton directory is switched off on this release.")

                return
            }

            let local = try room.localChildren().filter { !LocalDirectory.systemEntryNames.contains($0.name) }
            #expect(local.isEmpty, "The domain root should be empty but holds: \(local.map(\.name).joined(separator: ", "))")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `The domain is gone once a client starts without the account.`(_ underTest: ServerUnderTest) async throws {
        let room = try await CleanRoom.build(underTest, testName: "DomainLifecycle.domainDisappears")
        let domain = room.domain
        try await room.tearDown()

        // Quitting the client leaves the domain behind. What removes it is a client which starts and finds nothing claiming it, which is why the removal is observed here rather than in the teardown.
        #expect(try LocalDirectory.exists(domain), "The domain should still be there while no client has run since the account was removed.")

        try await ClientReset.reapDomainsWithoutAccounts(timeout: LiveEnvironment.scaled(.seconds(60)))

        #expect(try !LocalDirectory.exists(domain), "The domain directory at \(domain.path(percentEncoded: false)) survived a client start without its account.")
    }
}
