// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``ClientLaunchConfiguration``.
///
/// The command line options are the whole interface to the client, so their spelling is pinned down here. A silent change to it would otherwise show up as a client which starts but is not configured, which looks like a synchronisation failure.
///
@Suite("Client launch configuration")
struct ClientLaunchConfigurationTests {
    ///
    /// A configuration with an account, as a clean room builds it.
    ///
    static let configured = ClientLaunchConfiguration(account: ClientAccount(serverAddress: URL(string: "http://localhost:8080")!, userIdentifier: "suite-test-0badcafe", appPassword: "secret"))

    @Test
    func `An account is passed as command line options.`() {
        let arguments = Self.configured.arguments

        #expect(arguments.contains("--serverurl"))
        #expect(arguments.contains("http://localhost:8080"))
        #expect(arguments.contains("--userid"))
        #expect(arguments.contains("suite-test-0badcafe"))
        #expect(arguments.contains("--apppassword"))
        #expect(arguments.contains("secret"))
    }

    @Test
    func `Virtual files are switched on, because the File Provider is the subject.`() throws {
        let arguments = Self.configured.arguments
        let index = try #require(arguments.firstIndex(of: "--isvfsenabled"))

        #expect(arguments[index + 1] == "1")
    }

    @Test
    func `Logging is always verbose and flushed.`() {
        let arguments = Self.configured.arguments

        #expect(arguments.contains("--logdebug"))
        #expect(arguments.contains("--logflush"))
    }

    @Test
    func `No directory of our own is passed, because the sandboxed client could not use one.`() {
        let arguments = Self.configured.arguments

        #expect(!arguments.contains("--confdir"))
        #expect(!arguments.contains("--logdir"))
    }

    @Test
    func `A launch without an account configures nothing.`() {
        let arguments = ClientLaunchConfiguration().arguments

        #expect(!arguments.contains("--serverurl"))
        #expect(!arguments.contains("--apppassword"))
        #expect(arguments.contains("--background"))
    }
}
