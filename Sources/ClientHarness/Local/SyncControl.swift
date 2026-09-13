// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Pauses and resumes the synchronisation of one item, the way an application editing a document does.
///
/// This is the contract macOS defines for an application which has a document open: pause the item so that synchronisation cannot change it underneath the editor, and resume when the document is stable again, saying what should happen if the server moved on in the meantime.
///
/// It matters to this suite for a reason which is easy to miss. The provider is only asked to fail an upload on a conflict when an application asked for that treatment by resuming with ``ResumeBehaviour/failingOnConflict``. Without it the documented behaviour is `preserveLocalChanges`, under which the local version is uploaded and the server "may create a conflict copy, or may automatically pick the winner" — so a test which merely arranges a divergence and waits is measuring a default rather than testing a contract, and is entitled to no opinion about which of the two happened.
///
/// Unlike blocking the whole extension, this needs nothing of the client: it is addressed by URL, needs no provider identity, and is exactly what a document-based application does.
///
/// What the family applies to is narrower than "any item", and narrower in a particular way: pausing is refused with `CocoaError.featureUnsupported` for a **regular, non-package directory**. A package is not excluded, because the system presents a bundle as a single item rather than as a tree. Files and bundles are eligible; plain folders are not. Worth knowing as a constraint rather than meeting it as a puzzling failure.
///
///
/// Nothing here answers `false` when it means "I could not find out". Both questions return an optional, and the reason is a scar rather than a preference: an earlier version answered `false` on an unreadable key, a broken accessor made every key unreadable, and the result was sixteen failures across four servers whose message read "the client does not advertise that an item's synchronisation can be paused". That sentence is a finished bug report about the client, produced by a read which never returned an answer. Four explanations were written and retracted before the reader itself was suspected.
///
public enum SyncControl {
    ///
    /// What should happen to an item's local changes when its synchronisation resumes.
    ///
    public enum ResumeBehaviour: Sendable {
        ///
        /// Upload the local version, and let the provider and server settle any disagreement however they see fit.
        ///
        /// The default, and the one under which a server's version may be replaced without anything being reported.
        ///
        case preservingLocalChanges

        ///
        /// Upload the local version, and fail rather than overwrite if the server has moved on.
        ///
        /// The only behaviour under which the provider is asked to detect a conflict at all. Available only on a paused item whose provider advertises support for it — see ``SyncControl/supportedControls(of:)``.
        ///
        case failingOnConflict

        ///
        /// Take the server's version and keep the local changes only as an alternate version.
        ///
        case droppingLocalChanges

        ///
        /// The value the file system call expects.
        ///
        var fileManagerBehaviour: NSFileManagerResumeSyncBehavior {
            switch self {
                case .preservingLocalChanges: .preserveLocalChanges
                case .failingOnConflict: .afterUploadWithFailOnConflict
                case .droppingLocalChanges: .dropLocalChanges
            }
        }
    }

    ///
    /// Stop synchronisation from touching one item.
    ///
    /// Pausing outlives the process which asked for it, so an item left paused stays paused. Whatever pauses an item has to resume it.
    ///
    /// - Parameters:
    ///     - url: The item to pause.
    ///
    /// - Throws: Whatever the file system raises. A busy provider refuses with `EBUSY`, and a plain directory is refused outright.
    ///
    public static func pause(_ url: URL) async throws {
        try await FileManager.default.pauseSyncForUbiquitousItem(at: url)
    }

    ///
    /// Let synchronisation touch an item again.
    ///
    /// - Parameters:
    ///     - url: The item to resume.
    ///     - behaviour: What should happen to the local changes.
    ///
    /// - Throws: Whatever the file system raises, including the conflict itself when resuming with ``ResumeBehaviour/failingOnConflict``.
    ///
    public static func resume(_ url: URL, behaviour: ResumeBehaviour = .preservingLocalChanges) async throws {
        try await FileManager.default.resumeSyncForUbiquitousItem(at: url, with: behaviour.fileManagerBehaviour)
    }

    ///
    /// Pause an item, do something to it, and resume it whatever happens.
    ///
    /// Two reasons to reach for this rather than pausing and resuming by hand.
    ///
    /// The first is that **a pause outlives the process which asked for it**. It is not tied to the lifetime of the caller: an item left paused by a test which threw, crashed or was killed stays paused, with no upload and no download, silently, for everything which touches it afterwards — including the next run. So the resume belongs in a path which runs unconditionally rather than in the path where everything went well.
    ///
    /// The second is attribution. Pausing, the body and resuming fail in ways which look alike once they have been flattened into one `do` block, and a report which cannot say which of the three raised is a report nobody can act on. Here, pausing and resuming raise ``SyncControlFailure`` while the body's own errors pass through untouched.
    ///
    /// When resuming with the requested behaviour fails, the item is resumed again with ``ResumeBehaviour/droppingLocalChanges`` before the failure is raised, because an item whose resume failed is still paused.
    ///
    /// - Parameters:
    ///     - url: The item to pause.
    ///     - behaviour: What should happen to the local changes once the body is done.
    ///     - body: What to do while the item is paused.
    ///
    /// - Returns: Whatever the body returns.
    ///
    /// - Throws: ``SyncControlFailure`` if pausing or resuming failed, or whatever the body raised.
    ///
    @discardableResult
    public static func withPaused<T>(_ url: URL, resumingWith behaviour: ResumeBehaviour = .preservingLocalChanges, _ body: () async throws -> T) async throws -> T {
        do {
            try await pause(url)
        } catch {
            throw SyncControlFailure.pausing(error)
        }

        let value: T

        do {
            value = try await body()
        } catch {
            // The point of the pause was abandoned, so there is nothing to preserve and everything to unblock.
            try? await resume(url, behaviour: .droppingLocalChanges)

            throw error
        }

        do {
            try await resume(url, behaviour: behaviour)
        } catch {
            try? await resume(url, behaviour: .droppingLocalChanges)

            throw SyncControlFailure.resuming(error)
        }

        return value
    }

    ///
    /// Whether synchronisation of an item is currently paused.
    ///
    /// Worth asserting on a fixture before using it. An item inherited in a paused state does not announce itself: it simply never synchronises, and the tests which notice are the ones several cases later which were never about pausing at all.
    ///
    /// Read through the typed accessor, which works here — but fall back to `NSURL` if it answers nothing, because its immediate neighbour ``supportedControls(of:)`` does not bridge and the cost of being wrong about which of the two this is has already been paid once.
    ///
    /// - Parameters:
    ///     - url: The item to ask about.
    ///
    /// - Returns: Whether it is paused, or `nil` if the key is absent — the ordinary answer for anything outside a File Provider domain.
    ///
    public static func isPaused(_ url: URL) -> Bool? {
        if let value = try? url.resourceValues(forKeys: [.ubiquitousItemIsSyncPausedKey]).ubiquitousItemIsSyncPaused {
            return value
        }

        var value: AnyObject?

        try? (url as NSURL).getResourceValue(&value, forKey: .ubiquitousItemIsSyncPausedKey)

        return (value as? NSNumber)?.boolValue
    }

    ///
    /// What an item can be asked to do.
    ///
    /// Read through `NSURL` rather than through `URLResourceValues`, which is not a style preference. The typed accessor `ubiquitousItemSupportedSyncControls` returns `nil` even when the key is populated: on the same item, at the same moment, `allValues[.ubiquitousItemSupportedSyncControlsKey]` and `NSURL.getResourceValue(_:forKey:)` both hand back `3` — both controls — while the typed property hands back nothing. Only that one accessor fails to bridge; its sibling `ubiquitousItemIsSyncPaused` is fine.
    ///
    /// This cost a day and very nearly cost a wrong bug report. Reading through the typed accessor made every control read as unsupported on every server, which looked exactly like a client which advertises nothing — an explanation which even accounted for the puzzling part, that a capability the extension's `Info.plist` genuinely declares also read as absent. It was one broken accessor reporting nothing for both bits.
    ///
    /// - Parameters:
    ///     - url: The item to ask about.
    ///
    /// - Returns: What the item advertises, or `nil` if the key is absent — which is the ordinary answer for anything outside a File Provider domain, and for a directory.
    ///
    public static func supportedControls(of url: URL) -> NSFileManagerSupportedSyncControls? {
        var value: AnyObject?

        try? (url as NSURL).getResourceValue(&value, forKey: .ubiquitousItemSupportedSyncControlsKey)

        guard let number = value as? NSNumber else {
            return nil
        }

        return NSFileManagerSupportedSyncControls(rawValue: number.uintValue)
    }

    ///
    /// Whether the provider of an item can be asked to fail an upload rather than overwrite a changed server version.
    ///
    /// - Parameters:
    ///     - url: The item to ask about.
    ///
    /// - Returns: `true` or `false` as the item advertises it, or `nil` if the key could not be read at all — which is not the same answer and must not be flattened into one.
    ///
    public static func supportsFailingOnConflict(_ url: URL) -> Bool? {
        supportedControls(of: url)?.contains(.failUploadOnConflict)
    }

    ///
    /// Whether the provider of an item can be asked to pause synchronisation of it.
    ///
    /// - Parameters:
    ///     - url: The item to ask about.
    ///
    /// - Returns: `true` or `false` as the item advertises it, or `nil` if the key could not be read at all — which is not the same answer and must not be flattened into one.
    ///
    public static func supportsPausing(_ url: URL) -> Bool? {
        supportedControls(of: url)?.contains(.pauseSync)
    }
}
