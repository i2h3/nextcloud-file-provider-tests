// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import NextcloudContainerManager
import Rainmaker

///
/// A Nextcloud server deployed for the duration of one run.
///
/// One of these exists per entry of the matrix. Deployment, the removal of the demo content and the teardown all belong to the runner; the users the tests actually work with are created later, one per test case, through ``TestUser``.
///
public struct ManagedServer: Sendable {
    ///
    /// The user name of the administrative account the container image creates.
    ///
    public static let adminUser = "admin"

    ///
    /// The password of the administrative account the container image creates.
    ///
    public static let adminPassword = "admin"

    ///
    /// The deployed container.
    ///
    public let container: NextcloudContainer

    ///
    /// The description handed to the test process for this server.
    ///
    public let descriptor: ServerUnderTest

    ///
    /// The release this server reported when it finished installing, such as `34.0.3`.
    ///
    /// Read from the server rather than inferred from the tag it was deployed under, because `latest` is a moving target and the whole point of asking is to find out what it currently moves to.
    ///
    public let versionString: String

    ///
    /// A Rainmaker client authenticated as the administrative account.
    ///
    public var administration: Server {
        Server(address: descriptor.serverAddress, password: Self.adminPassword, user: Self.adminUser)
    }

    ///
    /// Deploy a server and prepare it for the suite.
    ///
    /// Preparation means one thing: the skeleton directory is emptied, so that every user created afterwards starts with a genuinely empty files root. The demo content Nextcloud ships would otherwise appear in every domain and quietly become part of assertions which never asked for it.
    ///
    /// The host port is whatever the kernel has free. It used to be pinned, because macOS names a File Provider domain after the server it belongs to — `Nextcloud-127.0.0.1:<port>-<user>` — and asks for privacy consent once per name, so a port which moved between runs meant a fresh domain to consent to every time. Full Disk Access, which this suite requires anyway, settles that consent for every domain at once and makes the address stability pointless. The two facts hold each other up: were Full Disk Access ever to stop being a requirement, the ports would have to be pinned again.
    ///
    /// - Parameters:
    ///     - tag: The Docker image tag of the release to deploy.
    ///     - isPushEnabled: Whether to deploy the High Performance Backend for Files alongside it.
    ///
    /// - Returns: The deployed server.
    ///
    /// - Throws: Whatever deployment or the preparation command raises.
    ///
    public static func deploy(tag: String, isPushEnabled: Bool) async throws -> ManagedServer {
        let configuration = NextcloudConfiguration(tag: tag, pushNotifications: isPushEnabled)
        let container = try await NextcloudContainerManager.deploy(configuration: configuration)

        // The loopback address is spelled out rather than named. `localhost` resolves to both `::1` and `127.0.0.1`, the container runtime publishes its port on IPv4 only, and the client — unlike curl, which falls back between the two — waits on the IPv6 attempt until whatever asked it gives up. What that looks like from outside is an account setup which sends one request and never logs a reply, then a File Provider domain which never appears, and it cost a day of looking at privacy grants, entitlements and code signatures before the wizard was pointed at `127.0.0.1` by hand and connected at once.
        //
        // A name would be friendlier to read in a log. It is the wrong trade: the address below is a fact about where the container is listening, and a name is a question asked of a resolver whose answer has already been wrong once.
        guard let address = URL(string: "http://127.0.0.1:\(container.port)") else {
            try? await NextcloudContainerManager.delete(container.id)

            throw ManagedServerError.addressNotFormable(port: container.port)
        }

        do {
            // The installation is awaited before the server is described, because what it reports while finishing is where the version in that description comes from.
            let status = try await awaitInstallation(inContainer: container.id, tag: tag)

            let server = ManagedServer(
                container: container,
                descriptor: ServerUnderTest(
                    tag: tag,
                    serverAddress: address,
                    containerIdentifier: container.id,
                    adminUser: adminUser,
                    adminPassword: adminPassword,
                    isPushEnabled: isPushEnabled,
                    versionString: status.versionString
                ),
                versionString: status.versionString
            )

            try await server.emptySkeleton()
            try await server.waitUntilReachable()

            return server
        } catch {
            // A container which could not be prepared is of no use to anyone and would otherwise be left behind, because the caller never received it and cannot tear it down.
            try? await NextcloudContainerManager.delete(container.id)

            throw error
        }
    }

    ///
    /// Wait until the installation inside the container is complete.
    ///
    /// The container answers on its port well before it is ready, and it passes through two distinct stages of not being ready: first the image's entry point is still unpacking Nextcloud into the web root, where any `occ` invocation fails with `Could not open input file: occ`, and then `occ` exists but the installation has not run, where it offers only a handful of commands and rejects everything else. Only `occ status` reporting the installation as present distinguishes a usable server from both.
    ///
    /// - Parameters:
    ///     - containerIdentifier: The container to ask.
    ///     - tag: The release being waited for, for the description of the wait.
    ///     - timeout: How long to wait.
    ///
    /// - Returns: What the server reported once it was installed.
    ///
    /// - Throws: ``WaitTimeoutError`` if the installation does not finish in time.
    ///
    public static func awaitInstallation(inContainer containerIdentifier: String, tag: String, timeout: Duration = .seconds(300)) async throws -> ServerStatus {
        try await Waiter.waitForValue("Nextcloud \(tag) is installed in its container", timeout: timeout) {
            // Before the installation finishes, `occ` answers with a limited set of commands and reports the installation as absent, so the exit status alone says nothing. Asking for JSON is what makes the version usable as well: the default output is a bullet list whose spacing has changed between releases.
            guard let result = try? await NextcloudContainerManager.runOCC(["status", "--output=json"], inContainer: containerIdentifier) else {
                return nil
            }

            guard let status = ServerStatus.decode(result.standardOutput), status.isInstalled else {
                return nil
            }

            return status
        }
    }

    ///
    /// Remove the demo content new users would otherwise be given.
    ///
    /// - Throws: Whatever the command raises.
    ///
    public func emptySkeleton() async throws {
        try await NextcloudContainerManager.runOCC(["config:system:set", "skeletondirectory", "--value="], inContainer: descriptor.containerIdentifier)
    }

    ///
    /// Wait until the server answers requests.
    ///
    /// - Parameters:
    ///     - timeout: How long to wait.
    ///
    /// - Throws: ``WaitTimeoutError`` if the server does not answer in time.
    ///
    public func waitUntilReachable(timeout: Duration = .seconds(120)) async throws {
        let server = administration

        try await Waiter.waitUntil("the server at \(descriptor.serverAddress.absoluteString) answers", timeout: timeout) {
            do {
                _ = try await server.capabilities()

                return true
            } catch {
                return false
            }
        }
    }

    ///
    /// Copy the server's own log out of the container.
    ///
    /// - Returns: The location of the copied log file.
    ///
    /// - Throws: Whatever copying raises.
    ///
    public func logFile() async throws -> URL {
        try await NextcloudContainerManager.logFile(inContainer: descriptor.containerIdentifier)
    }

    ///
    /// Delete the container.
    ///
    /// - Throws: Whatever deletion raises.
    ///
    public func delete() async throws {
        try await NextcloudContainerManager.delete(descriptor.containerIdentifier)
    }

    ///
    /// Delete a container by its identifier.
    ///
    /// A session prepared for Xcode outlives the process which deployed it, so its containers have to be removable from nothing but what was written down about them.
    ///
    /// - Parameters:
    ///     - containerIdentifier: The container to delete.
    ///
    /// - Throws: Whatever the deletion raises.
    ///
    public static func delete(containerIdentifier: String) async throws {
        try await NextcloudContainerManager.delete(containerIdentifier)
    }

    ///
    /// Create a deployed server.
    ///
    /// - Parameters:
    ///     - container: The deployed container.
    ///     - descriptor: The description handed to the test process.
    ///     - versionString: The release the server reported.
    ///
    public init(container: NextcloudContainer, descriptor: ServerUnderTest, versionString: String) {
        self.versionString = versionString
        self.container = container
        self.descriptor = descriptor
    }
}
