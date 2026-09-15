// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation

///
/// What a scenario's precondition left behind, and everything an oracle needs to judge what happens to it.
///
/// Built once by ``ScenarioWorld`` and then read. The identity fields in particular are captured at the last moment before the operation, because after a rename the item's previous identity is unrecoverable and an oracle which wanted to compare has nothing to compare against.
///
struct ScenarioSubject {
    ///
    /// The name the item has before the operation.
    ///
    let name: String

    ///
    /// The container it sits in, as the server spells it.
    ///
    let parentRemotePath: String

    ///
    /// The container it sits in, relative to the domain.
    ///
    /// Empty for the domain root, which is the spelling ``CleanRoom/localChildren(of:)`` and ``CleanRoom/localURL(of:)`` expect.
    ///
    let parentLocalPath: String

    ///
    /// What the server said about the item immediately before the operation.
    ///
    /// Carries `oc:fileid`, which is what an identity assertion compares. Read from Rainmaker's `Item.instanceId`, which is inverted from what its name suggests — `Item.id` is `oc:id` and is the wrong field for this.
    ///
    let before: RemoteEntry

    ///
    /// The content the item was created with, for the kinds which have any.
    ///
    let fingerprint: String?

    ///
    /// Where the item is going, for a cell which moves it, as the server spells it.
    ///
    /// Present only for a ``ScenarioMatrix/Site/transfer(from:to:)``. A move is the one operation whose cell describes two places rather than one, and the realization it pins is the state of the two **parents** rather than of the item.
    ///
    let destinationRemotePath: String?

    ///
    /// Where the item is going, relative to the domain.
    ///
    let destinationLocalPath: String?

    ///
    /// Whether this test ever enumerated the item, for the kinds where that is what realization means.
    ///
    /// A directory is realized by being entered, so for a directory this is the record of whether the precondition holds — and it is a record of what the *test* did rather than of what the item is, which is the honest thing to assert and the only thing available.
    ///
    let wasEnumerated: Bool

    ///
    /// Where the item would land on the server after a move, under its own name.
    ///
    var destinationPath: String? {
        guard let destinationRemotePath else {
            return nil
        }

        return destinationRemotePath == "/" ? "/\(name)" : "\(destinationRemotePath)/\(name)"
    }

    ///
    /// Where the item would land in the domain after a move.
    ///
    var destinationLocal: String? {
        guard let destinationLocalPath else {
            return nil
        }

        return destinationLocalPath.isEmpty ? name : "\(destinationLocalPath)/\(name)"
    }

    ///
    /// Where the item is on the server before the operation.
    ///
    var remotePath: String {
        parentRemotePath == "/" ? "/\(name)" : "\(parentRemotePath)/\(name)"
    }

    ///
    /// Where a named sibling would be on the server.
    ///
    /// - Parameters:
    ///     - other: The name.
    ///
    /// - Returns: The path.
    ///
    func remotePath(of other: String) -> String {
        parentRemotePath == "/" ? "/\(other)" : "\(parentRemotePath)/\(other)"
    }

    ///
    /// Where a named sibling would be in the domain.
    ///
    /// - Parameters:
    ///     - other: The name.
    ///
    /// - Returns: The path relative to the domain.
    ///
    func localPath(of other: String) -> String {
        parentLocalPath.isEmpty ? other : "\(parentLocalPath)/\(other)"
    }
}
