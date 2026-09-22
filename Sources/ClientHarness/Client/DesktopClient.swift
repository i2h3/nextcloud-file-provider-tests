// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Starts and stops the desktop client under test.
///
/// The client is always the signed build at ``ClientPaths/application`` and it is always driven through its documented command line options, never through its window. That keeps the setup headless, and it means the tests exercise the same account creation path an administrator would script.
///
public enum DesktopClient {
    ///
    /// Whether the client process is running.
    ///
    /// - Returns: `true` if at least one client process exists.
    ///
    public static func isRunning() async throws -> Bool {
        try await isProcessRunning(arguments: ["-x", "Nextcloud"])
    }

    ///
    /// Whether the File Provider extension process is running.
    ///
    /// The extension outlives the client for a moment after a quit and is started by the system rather than by the client, so a clean shutdown means both are gone.
    ///
    /// - Returns: `true` if at least one extension process exists.
    ///
    public static func isExtensionRunning() async throws -> Bool {
        try await isProcessRunning(arguments: ["-f", ClientPaths.fileProviderExtensionBundleIdentifier])
    }

    ///
    /// The marketing version of the installed client.
    ///
    /// - Returns: The version string from the bundle's `Info.plist`, or `nil` if it cannot be read.
    ///
    public static func installedVersion() -> String? {
        let informationURL = ClientPaths.application.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)

        guard let data = try? Data(contentsOf: informationURL) else {
            return nil
        }

        guard let information = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        return information["CFBundleShortVersionString"] as? String
    }

    ///
    /// Launch the client with a configuration.
    ///
    /// - Parameters:
    ///     - configuration: How this launch is configured, including the account to create.
    ///
    /// - Throws: ``ProcessRunnerError`` if the client cannot be started.
    ///
    public static func launch(_ configuration: ClientLaunchConfiguration) async throws {
        var arguments = ["-n", "-a", ClientPaths.application.path(percentEncoded: false), "--args"]
        arguments += configuration.arguments

        try await ProcessRunner.runSuccessfully(URL(filePath: "/usr/bin/open"), arguments: arguments)
    }

    ///
    /// Configure an account and wait for the client to finish doing so.
    ///
    /// Account setup from the command line is a one-shot provisioning mode: the client starts, creates the account, and exits by itself. It does not create the File Provider domain in that run — the settings controller does not yet know the account at that point — so a second, ordinary launch is what turns the configured account into a domain.
    ///
    /// - Parameters:
    ///     - account: The account to configure.
    ///     - timeout: How long to wait for the provisioning run to finish before quitting it.
    ///
    /// - Throws: Whatever launching or quitting the client raises.
    ///
    public static func provisionAccount(_ account: ClientAccount, timeout: Duration = .seconds(60)) async throws {
        try await launch(ClientLaunchConfiguration(account: account))

        do {
            try await Waiter.waitUntil("the client has finished configuring the account and exited", timeout: timeout) {
                let isClientRunning = try await isRunning()

                return !isClientRunning
            }
        } catch {
            // A client which stayed up did not necessarily fail; quitting it leads to the same state as the exit it usually performs on its own.
            try await quit()
        }

        // Whether the account was actually configured is a different question from whether the client exited, and until this check existed the two were answered together. A client whose setup request never came back exits — or is quitted here — exactly like one which succeeded, and the run then spent another two minutes waiting for a domain which nothing had asked for, before reporting the absence of the domain rather than the absence of the account.
        let configured = ClientConfigurationFile.accounts(in: ClientPaths.configurationFile)

        guard configured.contains(where: { $0.hasPrefix("\(account.userIdentifier)@") }) else {
            throw AccountProvisioningFailure(account: account, configured: configured)
        }
    }

    ///
    /// Quit the client and wait for it and its extension to be gone.
    ///
    /// The client is asked to quit through its own option first. Only if it does not comply within the timeout is it signalled, because a killed client leaves its domain in whatever state it was in and the next test would inherit that.
    ///
    /// - Parameters:
    ///     - timeout: How long to wait for a graceful shutdown before signalling the processes.
    ///
    /// - Throws: ``WaitTimeoutError`` if the processes are still there after being signalled.
    ///
    public static func quit(timeout: Duration = .seconds(30)) async throws {
        guard try await isRunning() else {
            return
        }

        try await ProcessRunner.run(URL(filePath: "/usr/bin/open"), arguments: ["-n", "-a", ClientPaths.application.path(percentEncoded: false), "--args", "--quit"])

        do {
            try await Waiter.waitUntil("the client and its File Provider extension have quit", timeout: timeout) {
                let isClientRunning = try await isRunning()
                let isProviderRunning = try await isExtensionRunning()

                return !isClientRunning && !isProviderRunning
            }
        } catch {
            try await ProcessRunner.run(URL(filePath: "/usr/bin/pkill"), arguments: ["-x", "Nextcloud"])

            // Both, as in the wait above. This one asked only about the client, and `pkill -x Nextcloud` does not touch the extension — it runs as its own process under the system's management. So the path taken when the graceful wait times out could return success with the extension still alive, serving the domain of the room being torn down, while the next room wiped the configuration out from under it and started a client beside it.
            //
            // The graceful wait times out on the extension alone more readily than it sounds: the system reaps an extension some time after the client that hosted it, so a client which is already gone and an extension which is not is an ordinary moment rather than a strange one — and `pkill` is then a no-op which does nothing to the only process still running.
            //
            // Throwing here is what this method documents: "WaitTimeoutError if the processes are still there after being signalled". It stops being fatal to a room's teardown, which used to skip the log copying behind it and is now recorded instead.
            try await Waiter.waitUntil("the signalled client and its File Provider extension have terminated", timeout: .seconds(10)) {
                let isClientRunning = try await isRunning()
                let isProviderRunning = try await isExtensionRunning()

                return !isClientRunning && !isProviderRunning
            }
        }
    }

    ///
    /// Whether `pgrep` finds a process.
    ///
    /// - Parameters:
    ///     - arguments: The `pgrep` arguments selecting the process.
    ///
    /// - Returns: `true` if at least one process matches.
    ///
    private static func isProcessRunning(arguments: [String]) async throws -> Bool {
        let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/pgrep"), arguments: arguments)

        return result.isSuccess
    }
}
