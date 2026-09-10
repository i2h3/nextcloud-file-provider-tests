// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Returns this machine to a state in which no Nextcloud account is configured.
///
/// The order matters. A File Provider domain directory must not be deleted while the system still knows about the domain, so the client is quit first, its configuration is removed, and it is then started once more with an empty configuration directory: on startup it reaps the domains which no longer belong to any account. Only what is left afterwards is removed by hand.
///
/// The guard against destroying a configuration somebody cares about is an informed confirmation, not a refusal to run. These tests are meant to be written and debugged on an ordinary developer machine, so ``perform(backingUpTo:approval:)`` shows what it found, asks, and copies the existing configuration aside before removing it.
///
public enum ClientReset {
    ///
    /// The directories holding client state which a reset removes.
    ///
    public static var stateDirectories: [URL] {
        [
            ClientPaths.configurationDirectory,
            ClientPaths.applicationSupport,
            ClientPaths.caches,
            ClientPaths.groupContainer,
        ] + ClientPaths.extensionContainers
    }

    ///
    /// What the client currently has on this machine.
    ///
    /// - Returns: The inventory a confirmation prompt is built from.
    ///
    public static func inventory() async throws -> ClientInventory {
        let isClientRunning = try await DesktopClient.isRunning()
        let isProviderRunning = try await DesktopClient.isExtensionRunning()

        return try await ClientInventory(
            accounts: ClientConfigurationFile.accounts(in: ClientPaths.configurationFile),
            domainDirectories: clientDomainDirectories(),
            stateDirectories: stateDirectories.filter { LocalDirectory.exists($0) },
            hasKeychainCredentials: hasKeychainCredentials(),
            isRunning: isClientRunning || isProviderRunning
        )
    }

    ///
    /// Remove every trace of a configured account from this machine.
    ///
    /// - Parameters:
    ///     - backupDirectory: Where to copy the existing configuration to before removing it, if there is one. Pass `nil` to skip the copy.
    ///     - approval: Asked once with the inventory before anything is removed. Returning `false` cancels the reset.
    ///
    /// - Returns: `true` if the reset ran, `false` if it was declined.
    ///
    /// - Throws: Whatever quitting the client, removing the state or reaping the domains raises.
    ///
    @discardableResult
    public static func perform(backingUpTo backupDirectory: URL? = nil, approval: (ClientInventory) async -> Bool) async throws -> Bool {
        let inventory = try await inventory()

        guard !inventory.isEmpty else {
            return true
        }

        guard await approval(inventory) else {
            return false
        }

        if let backupDirectory {
            try backUpConfiguration(to: backupDirectory)
        }

        try await DesktopClient.quit()

        for directory in stateDirectories {
            try? FileManager.default.removeItem(at: directory)
        }

        try await removeKeychainCredentials()
        try await reapDomainsWithoutAccounts()

        for directory in clientDomainDirectories() {
            try? FileManager.default.removeItem(at: directory)
        }

        return true
    }

    ///
    /// Copy the client's current configuration aside so that it can be restored by hand.
    ///
    /// - Parameters:
    ///     - backupDirectory: The directory to copy into. It is created if it does not exist.
    ///
    /// - Throws: Whatever copying raises.
    ///
    public static func backUpConfiguration(to backupDirectory: URL) throws {
        guard LocalDirectory.exists(ClientPaths.configurationDirectory) else {
            return
        }

        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let destination = backupDirectory.appending(path: ClientPaths.configurationDirectory.lastPathComponent, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: ClientPaths.configurationDirectory, to: destination)
    }

    ///
    /// The mounted domain directories which appear to belong to the desktop client.
    ///
    /// Attribution is by name, because the system owns the naming of these directories and does not offer a way for a third process to ask who a domain belongs to. Everything else mounted under `CloudStorage` belongs to other providers and is left strictly alone.
    ///
    /// - Returns: The domain directories to remove.
    ///
    public static func clientDomainDirectories() -> [URL] {
        DomainLocator.mountedDomains().filter { $0.lastPathComponent.lowercased().hasPrefix("nextcloud") }
    }

    ///
    /// Start the client once so that it reaps the domains which no longer belong to an account, then quit it again.
    ///
    /// A File Provider domain outlives the account it was made for: quitting the client does not remove it, and the directory cannot simply be deleted while the system still knows about the domain. What removes it is the client noticing, at startup, that nothing claims it. This is therefore the only way to observe a domain disappear, and it is what makes a clean room's leftovers vanish before the next one is built.
    ///
    /// - Parameters:
    ///     - timeout: How long to give the client to reap.
    ///
    /// - Throws: Whatever launching or quitting the client raises.
    ///
    public static func reapDomainsWithoutAccounts(timeout: Duration = .seconds(30)) async throws {
        try await DesktopClient.launch(ClientLaunchConfiguration())

        try? await Waiter.waitUntil("the client has reaped the domains without an account", timeout: timeout) {
            clientDomainDirectories().isEmpty
        }

        try await DesktopClient.quit()
    }

    ///
    /// Whether the Keychain holds at least one credential of the client.
    ///
    /// - Returns: `true` if an entry of ``ClientPaths/keychainService`` exists.
    ///
    private static func hasKeychainCredentials() async throws -> Bool {
        let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/security"), arguments: ["find-generic-password", "-s", ClientPaths.keychainService])

        return result.isSuccess
    }

    ///
    /// Remove every Keychain entry of the client.
    ///
    /// The tool removes one entry per invocation, so it is repeated until it reports that nothing is left. The repetition is bounded so that an unexpected failure cannot turn into an endless loop.
    ///
    /// - Throws: Whatever running the tool raises.
    ///
    private static func removeKeychainCredentials() async throws {
        for _ in 0 ..< 32 {
            let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/security"), arguments: ["delete-generic-password", "-s", ClientPaths.keychainService])

            guard result.isSuccess else {
                return
            }
        }
    }
}
