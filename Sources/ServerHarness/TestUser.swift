// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import NextcloudContainerManager
import Rainmaker
import Synchronization

///
/// The Nextcloud user one test case runs as.
///
/// Users are created when their test starts rather than up front, so that the cost of provisioning is spread across the run instead of becoming a long ramp before the first assertion. Each user exists only for its test and is deleted with it.
///
public struct TestUser: Sendable {
    ///
    /// How many users this process has provisioned so far.
    ///
    /// Counting here rather than in the tests is deliberate: a parameterized test runs its body once per argument under a single test name, and every one of those runs needs a user and therefore a File Provider domain of its own. Leaving that to each test to remember is how a test ends up sharing a domain directory with its own previous run and waiting two minutes for a directory which is already there.
    ///
    private static let provisioned = Mutex<Int>(0)

    ///
    /// The app password issued for the desktop client.
    ///
    /// The client is configured with an app password rather than with the account password, which is what a real installation ends up with after its login flow.
    ///
    public let appPassword: String

    ///
    /// The account password, which is the user name repeated.
    ///
    /// This is what `NextcloudContainerManager` sets when it creates a user, and it is safe in a container which exists for minutes on a developer machine.
    ///
    public let password: String

    ///
    /// The user name on the server.
    ///
    public let identifier: String

    ///
    /// A Rainmaker client authenticated as this user with its app password.
    ///
    /// - Parameters:
    ///     - server: The server the user lives on.
    ///
    /// - Returns: The client.
    ///
    public func client(on server: ServerUnderTest) -> Server {
        Server(address: server.serverAddress, password: appPassword, user: identifier)
    }

    ///
    /// The account for the desktop client to be configured with.
    ///
    /// - Parameters:
    ///     - server: The server the user lives on.
    ///
    /// - Returns: The account.
    ///
    public func account(on server: ServerUnderTest) -> ClientAccount {
        ClientAccount(serverAddress: server.serverAddress, userIdentifier: identifier, appPassword: appPassword)
    }

    ///
    /// Create the user of a test on a server.
    ///
    /// - Parameters:
    ///     - testName: The test the user belongs to, conventionally `<suite>.<test>`.
    ///     - server: The server to create the user on.
    ///
    /// - Returns: The created user.
    ///
    /// - Throws: Whatever creating the user or requesting an app password raises.
    ///
    public static func provision(for testName: String, on server: ServerUnderTest) async throws -> TestUser {
        let ordinal = provisioned.withLock { count in
            count += 1

            return count
        }

        let identifier = TestUserName.derive(from: testName, ordinal: ordinal)

        // The user identifier doubles as the password, which is safe in a container that exists for minutes on a developer machine and saves carrying a second secret around. That is also the convention `addUser` follows, so this is its behaviour rather than a coincidence worth restating by hand.
        try await NextcloudContainerManager.addUser(identifier, inContainer: server.containerIdentifier)
        let appPassword = try await requestAppPassword(for: identifier, password: identifier, on: server)

        return TestUser(identifier: identifier, password: identifier, appPassword: appPassword)
    }

    ///
    /// Delete the user again.
    ///
    /// - Parameters:
    ///     - server: The server the user lives on.
    ///
    /// - Throws: Whatever deleting the user raises.
    ///
    public func delete(on server: ServerUnderTest) async throws {
        try await NextcloudContainerManager.removeUser(identifier, inContainer: server.containerIdentifier)
    }

    ///
    /// Ask the server for an app password for an account.
    ///
    /// - Parameters:
    ///     - user: The user name.
    ///     - password: The account password to authenticate with.
    ///     - server: The server to ask.
    ///
    /// - Returns: The issued app password.
    ///
    /// - Throws: ``TestUserError`` if the server does not issue one.
    ///
    private static func requestAppPassword(for user: String, password: String, on server: ServerUnderTest) async throws -> String {
        let client = Server(address: server.serverAddress, password: password, user: user)
        var request = try client.makeOCSRequest(for: "core/getapppassword", method: .get)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)

        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw TestUserError.appPasswordNotIssued(user: user, reason: "The server answered with status \((response as? HTTPURLResponse)?.statusCode ?? -1).")
        }

        guard let envelope = try? JSONDecoder().decode(AppPasswordResponse.self, from: data) else {
            throw TestUserError.appPasswordNotIssued(user: user, reason: "The answer could not be decoded: \(String(data: data, encoding: .utf8) ?? "<no body>")")
        }

        return envelope.ocs.data.apppassword
    }

    ///
    /// Create a description of a provisioned user.
    ///
    /// - Parameters:
    ///     - identifier: The user name on the server.
    ///     - password: The account password.
    ///     - appPassword: The app password issued for the desktop client.
    ///
    public init(identifier: String, password: String, appPassword: String) {
        self.appPassword = appPassword
        self.identifier = identifier
        self.password = password
    }
}
