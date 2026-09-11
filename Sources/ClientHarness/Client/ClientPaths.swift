// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The fixed locations the desktop client and its extensions occupy on this machine.
///
/// They are constants rather than configuration on purpose. The client under test is always the signed build installed at ``application``: app extensions are not reliably loaded and activated from outside `/Applications`, so a copy elsewhere would not behave like a real installation.
///
/// Since version 34 the client is **App Sandboxed** — its code signature carries `com.apple.security.app-sandbox` — so none of its state is where an unsandboxed application would keep it. Everything lives inside ``container`` instead, and a path outside it is not writable by the client at all. That is why ``ClientLaunchConfiguration`` does not pass a configuration directory of its own and why ``ClientReset`` looks here rather than in `~/Library/Preferences`.
///
public enum ClientPaths {
    ///
    /// The application group the client shares with its extensions.
    ///
    /// The File Provider extension writes its per-domain defaults, such as the server address and the user, into this group's container. ``DomainDefaults`` reads them from there.
    ///
    public static let applicationGroupIdentifier = "NKUJUXUJ3B.com.nextcloud.desktopclient"

    ///
    /// The bundle identifier of the desktop client.
    ///
    public static let bundleIdentifier = "com.nextcloud.desktopclient"

    ///
    /// The bundle identifiers of the extensions shipped inside the client.
    ///
    /// The File Provider extension is the subject of these tests; the other two are listed because their containers are part of the state a reset has to remove.
    ///
    public static let extensionBundleIdentifiers = [
        "com.nextcloud.desktopclient.FileProviderExt",
        "com.nextcloud.desktopclient.FileProviderUIExt",
        "com.nextcloud.desktopclient.FinderSyncExt",
    ]

    ///
    /// The bundle identifier of the File Provider extension.
    ///
    /// It is the process to watch for when waiting for a clean shutdown: the client can be gone while the extension is still running.
    ///
    public static let fileProviderExtensionBundleIdentifier = "com.nextcloud.desktopclient.FileProviderExt"

    ///
    /// The Keychain service the client stores its account credentials under.
    ///
    public static let keychainService = "Nextcloud"

    ///
    /// The signed desktop client under test.
    ///
    public static let application = URL(filePath: "/Applications/Nextcloud.app", directoryHint: .isDirectory)

    ///
    /// The home directory of the user running the tests.
    ///
    public static let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)

    ///
    /// The directory macOS mounts File Provider domains in.
    ///
    /// Every domain of every provider appears here as one directory, which is why ``DomainLocator`` identifies the client's domains by comparing this directory before and after an account is added rather than by guessing a naming scheme.
    ///
    public static let cloudStorage = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)

    ///
    /// The sandbox container of the desktop client.
    ///
    public static let container = home.appending(path: "Library/Containers/\(bundleIdentifier)", directoryHint: .isDirectory)

    ///
    /// The part of the container the client may write to.
    ///
    /// Inside the sandbox this stands in for the home directory, so everything below it mirrors the layout an unsandboxed application would use directly.
    ///
    public static let containerData = container.appending(path: "Data", directoryHint: .isDirectory)

    ///
    /// The directory the client keeps its configuration in.
    ///
    public static let configurationDirectory = containerData.appending(path: "Library/Preferences/Nextcloud", directoryHint: .isDirectory)

    ///
    /// The configuration file holding the accounts.
    ///
    public static let configurationFile = configurationDirectory.appending(path: "nextcloud.cfg", directoryHint: .notDirectory)

    ///
    /// The directory the client writes its logs to.
    ///
    /// The client rotates and compresses the files in here, so a diagnostics bundle copies the whole directory rather than one file.
    ///
    public static let logDirectory = configurationDirectory.appending(path: "logs", directoryHint: .isDirectory)

    ///
    /// The client's application support directory inside the container.
    ///
    public static let applicationSupport = containerData.appending(path: "Library/Application Support/Nextcloud", directoryHint: .isDirectory)

    ///
    /// The client's cache directory inside the container.
    ///
    public static let caches = containerData.appending(path: "Library/Caches/Nextcloud", directoryHint: .isDirectory)

    ///
    /// The container shared by the client and its extensions through ``applicationGroupIdentifier``.
    ///
    public static let groupContainer = home.appending(path: "Library/Group Containers/\(applicationGroupIdentifier)", directoryHint: .isDirectory)

    ///
    /// Where the File Provider extension writes its own log, one directory per domain.
    ///
    /// Not in the extension's container, where its preferences are, but in the group container it shares with the client. Worth knowing because the two are easy to confuse and hold different things.
    ///
    public static let extensionLogs = groupContainer.appending(path: "File Provider Domains", directoryHint: .isDirectory)

    ///
    /// The containers of the client's extensions.
    ///
    public static var extensionContainers: [URL] {
        extensionBundleIdentifiers.map { home.appending(path: "Library/Containers/\($0)", directoryHint: .isDirectory) }
    }
}
