// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Rainmaker
import ServerHarness
import Synchronization
import Testing

///
/// Everything one test case gets to itself.
///
/// A clean room is a user which exists only for this test, a desktop client configured with nothing but that user's account, and the File Provider domain which results from it. Because the user's own files root is the workspace, there is no shared subtree to carve up and no cleanup which can leak into another test.
///
/// The client offers no way to remove an account from the command line, so a clean room is built the reliable way instead: the client is quit, handed a fresh configuration directory, and started again with the new account. That costs a client restart and a domain creation per test, which is the deliberate trade for tests which do not interfere with each other.
///
struct CleanRoom {
    ///
    /// Whether a clean room is standing right now.
    ///
    /// One machine has one desktop client and one File Provider domain at a time, so two tests cannot hold a room at once. The runner enforces that with `--no-parallel`, but Xcode runs tests in parallel unless told otherwise, and the failures which follow from two rooms overlapping look like anything except the scheduling problem they are. This turns them into one sentence which says what to switch off.
    ///
    private static let isOccupied = Mutex<Bool>(false)

    ///
    /// The account the desktop client was configured with.
    ///
    let account: ClientAccount

    ///
    /// A Rainmaker client authenticated as the administrator of the server.
    ///
    let administration: Server

    ///
    /// The directory of this test's File Provider domain.
    ///
    let domain: URL

    ///
    /// The ledger recording every directory this test enumerates.
    ///
    let ledger: EnumerationLedger

    ///
    /// A Rainmaker client authenticated as this test's own user.
    ///
    let server: Server

    ///
    /// The server this test runs against.
    ///
    let underTest: ServerUnderTest

    ///
    /// This test's own user.
    ///
    let user: TestUser

    ///
    /// What this room is, written beside the logs it leaves behind.
    ///
    /// Carried rather than rebuilt at teardown because only the moment the room began is worth recording, and by then it has passed.
    ///
    let manifest: RoomManifest

    ///
    /// Build a clean room, run a test in it, and tear it down again.
    ///
    /// Teardown runs whether the body succeeds or fails, and its own failures are raised rather than swallowed: a half-cleaned machine poisons every later test, so it has to be loud.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - testName: The test the room belongs to, conventionally `<suite>.<test>`. It names the user.
    ///     - body: The test itself.
    ///
    /// - Returns: Whatever the body returns.
    ///
    /// - Throws: Whatever building the room, the body or the teardown raises.
    ///
    @discardableResult
    static func with<Result>(_ underTest: ServerUnderTest, testName: String, _ body: (CleanRoom) async throws -> Result) async throws -> Result {
        let room = try await build(underTest, testName: testName)

        do {
            let result = try await body(room)
            try await room.tearDown()

            return result
        } catch {
            try? await room.tearDown()

            throw error
        }
    }

    ///
    /// Build a clean room.
    ///
    /// - Parameters:
    ///     - underTest: The server to run against.
    ///     - testName: The test the room belongs to.
    ///
    /// - Returns: The built room.
    ///
    /// - Throws: Whatever provisioning the user, launching the client or waiting for the domain raises.
    ///
    static func build(_ underTest: ServerUnderTest, testName: String) async throws -> CleanRoom {
        let environment = try LiveEnvironment.require()

        try isOccupied.withLock { occupied in
            guard !occupied else {
                throw CleanRoomError.concurrentCleanRoom
            }

            occupied = true
        }

        let ledger = EnumerationLedger()
        let user: TestUser
        let account: ClientAccount

        do {
            user = try await TestUser.provision(for: testName, on: underTest)
            account = user.account(on: underTest)
        } catch {
            isOccupied.withLock { $0 = false }

            throw error
        }

        // Written now rather than at teardown, so that a room which never finishes being built still says what it was trying to be. Those are the rooms whose logs matter most.
        var manifest = RoomManifest(
            testName: testName,
            testIdentifier: Test.current?.id.description,
            testDisplayName: Test.current?.displayName ?? Test.current?.name,
            user: user.identifier,
            server: RunManifestServer(underTest)
        )

        try? manifest.write(into: Self.roomDirectory(of: user.identifier, in: environment))

        do {
            try await DesktopClient.quit()

            // A room always starts synchronising. A test which blocks the client and then fails before unblocking it would otherwise hand the next test a client which never talks to its server, and that failure looks like a timeout rather than like anything to do with blocking.
            try await ClientSynchronisation.unblock()

            // Turned on before the client is started, so that the extension has it from its first breath. Its log is the only account of what the File Provider was asked to do and what it answered, and the failures worth having it for are the ones nobody thought to enable it for in advance.
            try await ClientLogging.enableDebugLogging()

            // The client is App Sandboxed and cannot be given a configuration directory of its own, so the clean room is made by emptying the one it insists on using. Seeding the File Provider mode into it decides by construction what would otherwise depend on whatever the client defaults to when it finds nothing.
            try? FileManager.default.removeItem(at: ClientPaths.configurationDirectory)
            try ClientConfigurationFile.writeFileProviderModeOnly(to: ClientPaths.configurationFile)

            let knownDomains = DomainLocator.mountedDomains()

            // Two launches, because that is what the client does: the first one configures the account and exits, the second one turns that account into a File Provider domain.
            try await DesktopClient.provisionAccount(account, timeout: environment.scaled(.seconds(60)))
            try await DesktopClient.launch(ClientLaunchConfiguration())

            let domain = try await waitForDomain(besides: knownDomains, ledger: ledger, timeout: environment.scaled(.seconds(120)))

            manifest.domainPath = domain.path(percentEncoded: false)
            try? manifest.write(into: Self.roomDirectory(of: user.identifier, in: environment))

            return CleanRoom(
                account: account,
                administration: Server(address: underTest.serverAddress, password: underTest.adminPassword, user: underTest.adminUser),
                domain: domain,
                ledger: ledger,
                server: user.client(on: underTest),
                underTest: underTest,
                user: user,
                manifest: manifest
            )
        } catch {
            // A room which fails to build has no teardown to run, so the user it already created would survive the test and make every later run of the same test fail at `user:add` instead of where the trouble actually is. One failure should stay one failure.
            try? await DesktopClient.quit()
            try? await user.delete(on: underTest)
            isOccupied.withLock { $0 = false }

            throw error
        }
    }

    ///
    /// Wait for the account's domain, or for the client to say that it will not configure the account.
    ///
    /// Racing the two is what turns a two-minute timeout into an immediate, explained failure. The client reports a refusal within a second of being asked, and that sentence is far more useful than the observation that nothing appeared.
    ///
    /// - Parameters:
    ///     - known: The domain directories which existed before the account was configured.
    ///     - ledger: The ledger to record the confirming enumeration in.
    ///     - timeout: How long to wait.
    ///
    /// - Returns: The directory of the new domain.
    ///
    /// - Throws: ``CleanRoomError/accountSetupFailed(reason:)`` if the client gives up, or ``WaitTimeoutError`` if nothing happens at all.
    ///
    static func waitForDomain(besides known: [URL], ledger: EnumerationLedger, timeout: Duration) async throws -> URL {
        let knownPaths = Set(known.map { $0.standardizedFileURL.path(percentEncoded: false) })

        let domain = try await Waiter.waitForValue("the account's File Provider domain appears", timeout: timeout) {
            if let failure = ClientLog.accountSetupFailure() {
                throw CleanRoomError.accountSetupFailed(reason: failure)
            }

            return DomainLocator.mountedDomains().first { !knownPaths.contains($0.standardizedFileURL.path(percentEncoded: false)) }
        }

        try await DomainLocator.confirmReadable(domain, ledger: ledger, timeout: timeout)

        return domain
    }

    ///
    /// Take the room down again.
    ///
    /// The domain directory is removed on a best-effort basis: while the system still knows about the domain it may refuse, in which case the client reaps it when the next test starts it with a configuration that no longer mentions the account. Spike S7 establishes whether that is reliable over a long run or whether a heavier reset is needed between tests.
    ///
    /// - Throws: Whatever quitting the client or deleting the user raises.
    ///
    func tearDown() async throws {
        // Released whatever happens, because a room which stayed marked as standing would make every later test fail as though the suites were running in parallel.
        defer {
            Self.isOccupied.withLock { $0 = false }
        }

        try await DesktopClient.quit()
        try? await ClientSynchronisation.unblock()
        try? await copyClientLogs()
        try? completeManifest()

        // The configuration goes, so that nothing claims this room's domain any more. The domain directory itself stays until a client starts and reaps it, which the next clean room does on the way in — see ``ClientReset/reapDomainsWithoutAccounts(timeout:)``.
        try? FileManager.default.removeItem(at: ClientPaths.configurationDirectory)

        try await user.delete(on: underTest)
    }

    ///
    /// Close this room's record, now that its life is over and its logs have been kept.
    ///
    /// The end of the window is what makes the record usable: a failure is attributed to a room by falling inside one, and rooms never overlap.
    ///
    /// - Throws: Whatever writing raises.
    ///
    private func completeManifest() throws {
        let environment = try LiveEnvironment.require()
        let directory = Self.roomDirectory(of: user.identifier, in: environment)

        var completed = manifest
        completed.endedAt = Date()
        completed.domainIdentifiers = (try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "extension-logs", directoryHint: .isDirectory).path(percentEncoded: false))) ?? []

        try completed.write(into: directory)
    }

    ///
    /// Where a clean room's artifacts are collected.
    ///
    /// - Parameters:
    ///     - user: The Nextcloud user the room created, which names its directory.
    ///     - environment: The run the room belongs to.
    ///
    /// - Returns: The directory, which may not exist yet.
    ///
    static func roomDirectory(of user: String, in environment: RunEnvironment) -> URL {
        environment.artifactsDirectory
            .appending(path: "clean-rooms", directoryHint: .isDirectory)
            .appending(path: user, directoryHint: .isDirectory)
    }

    ///
    /// Keep this test's share of the logs, which the next test would otherwise wipe along with the configuration directory.
    ///
    /// Two logs are kept, because they say different things. The client's own log is the account and the domain lifecycle. The extension's is what the File Provider actually did — every request the system made of it and what it answered — and it is the only account of the side of the conversation the client never sees. It is written per domain into the group container, and a domain outlives its test by no more than the next client start, so it has to be taken now or not at all.
    ///
    /// - Throws: Whatever copying raises.
    ///
    func copyClientLogs() async throws {
        let environment = try LiveEnvironment.require()

        let destination = Self.roomDirectory(of: user.identifier, in: environment)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        if try LocalDirectory.exists(ClientPaths.logDirectory) {
            let copy = destination.appending(path: "client-logs", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: ClientPaths.logDirectory, to: copy)
        }

        try copyExtensionLogs(to: destination.appending(path: "extension-logs", directoryHint: .isDirectory))
    }

    ///
    /// Keep the File Provider extension's own log for every domain it has one for.
    ///
    /// Only the log directories are taken, never the domain directory around them. That directory also holds the extension's Realm databases, which are open while the extension is running and refuse to be copied — and because a recursive copy of the whole tree reaches them before it reaches `Logs`, taking the lot means taking nothing.
    ///
    /// - Parameters:
    ///     - destination: The directory to collect the logs in.
    ///
    /// - Throws: Whatever creating the destination raises. A domain whose log cannot be copied is skipped rather than failing the collection, because a diagnostics bundle missing one log is worth more than no bundle at all.
    ///
    private func copyExtensionLogs(to destination: URL) throws {
        guard try LocalDirectory.exists(ClientPaths.extensionLogs) else {
            return
        }

        let domains = (try? FileManager.default.contentsOfDirectory(atPath: ClientPaths.extensionLogs.path(percentEncoded: false))) ?? []

        for domain in domains {
            let logs = ClientPaths.extensionLogs
                .appending(path: domain, directoryHint: .isDirectory)
                .appending(path: "Logs", directoryHint: .isDirectory)

            guard try LocalDirectory.exists(logs) else {
                continue
            }

            let copy = destination.appending(path: domain, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: logs, to: copy)
        }
    }

    ///
    /// List one directory level inside the domain, recording the enumeration.
    ///
    /// - Parameters:
    ///     - path: The directory to list, relative to the domain root. Defaults to the root itself.
    ///
    /// - Returns: The entries found.
    ///
    /// - Throws: Whatever reading the directory raises.
    ///
    func localChildren(of path: String = "") throws -> [LocalNode] {
        try LocalDirectory.children(of: localURL(of: path), ledger: ledger)
    }

    ///
    /// The location of an item inside the domain.
    ///
    /// - Parameters:
    ///     - path: The path relative to the domain root.
    ///
    /// - Returns: The location.
    ///
    func localURL(of path: String) -> URL {
        guard !path.isEmpty else {
            return domain
        }

        return domain.appending(path: path, directoryHint: .inferFromPath)
    }

    ///
    /// List one directory level on the server.
    ///
    /// - Parameters:
    ///     - path: The directory to list, relative to the user's files root. Defaults to the root itself.
    ///
    /// - Returns: The entries the server reports.
    ///
    /// - Throws: Whatever the request raises.
    ///
    func remoteChildren(of path: String = "/") async throws -> [RemoteEntry] {
        try await RemoteListing.children(of: path, on: server)
    }

    ///
    /// Wait until the server reports an entry of a given name.
    ///
    /// - Parameters:
    ///     - name: The name to wait for.
    ///     - path: The directory to look in. Defaults to the user's files root.
    ///     - timeout: How long to wait.
    ///
    /// - Returns: The entry.
    ///
    /// - Throws: ``WaitTimeoutError`` if it does not appear in time.
    ///
    @discardableResult
    func waitForRemoteEntry(named name: String, in path: String = "/", timeout: Duration = LiveEnvironment.scaled(.seconds(60))) async throws -> RemoteEntry {
        var found: RemoteEntry?

        try await Waiter.poll("the server reports \"\(name)\" in \(path)", timeout: timeout) {
            found = try await remoteChildren(of: path).first { $0.name == name }

            return found != nil
        }

        guard let found else {
            throw WaitTimeoutError(expectation: "the server reports \"\(name)\" in \(path)", timeout: timeout)
        }

        return found
    }

    ///
    /// Wait until the server no longer reports an entry of a given name.
    ///
    /// - Parameters:
    ///     - name: The name to wait for the disappearance of.
    ///     - path: The directory to look in. Defaults to the user's files root.
    ///     - timeout: How long to wait.
    ///
    /// - Throws: ``WaitTimeoutError`` if it is still there afterwards.
    ///
    func waitForRemoteRemoval(of name: String, in path: String = "/", timeout: Duration = LiveEnvironment.scaled(.seconds(60))) async throws {
        try await Waiter.poll("the server no longer reports \"\(name)\" in \(path)", timeout: timeout) {
            try await !remoteChildren(of: path).contains { $0.name == name }
        }
    }

    ///
    /// The fingerprint of a file as the server has it.
    ///
    /// - Parameters:
    ///     - path: The file, relative to the user's files root.
    ///
    /// - Returns: The hexadecimal SHA-256 digest of what the server stores.
    ///
    /// - Throws: Whatever downloading raises.
    ///
    func remoteFingerprint(of path: String) async throws -> String {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try await server.download(path, to: directory, force: true)
        let name = path.split(separator: "/").last.map(String.init) ?? path

        return try ContentFactory.fingerprintOfFile(at: directory.appending(path: name, directoryHint: .notDirectory))
    }

    ///
    /// Collect a diagnostics bundle for this test.
    ///
    /// - Parameters:
    ///     - reason: Why the bundle is being collected.
    ///     - focus: The item the failure was about, if there is a single one.
    ///
    /// - Returns: The directory the bundle was written to.
    ///
    /// - Throws: Whatever collecting raises.
    ///
    @discardableResult
    func collectDiagnostics(reason: String, focus: URL? = nil) async throws -> URL {
        let environment = try LiveEnvironment.require()

        let directory = environment.artifactsDirectory
            .appending(path: "diagnostics", directoryHint: .isDirectory)
            .appending(path: user.identifier, directoryHint: .isDirectory)

        let serverLog = try? await NextcloudServerLog.copy(of: underTest, into: directory)

        return try await DiagnosticsBundle.collect(
            into: directory,
            ledger: ledger,
            clientLogDirectory: ClientPaths.logDirectory,
            focus: focus,
            notes: [
                "Reason": reason,
                "Server": underTest.description,
                "Server address": underTest.serverAddress.absoluteString,
                "User": user.identifier,
                "Domain": domain.path(percentEncoded: false),
                "Server log": serverLog?.path(percentEncoded: false) ?? "not available",
            ]
        )
    }
}
