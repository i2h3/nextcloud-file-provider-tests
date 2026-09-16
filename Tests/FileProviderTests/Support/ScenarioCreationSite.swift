// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What a create's precondition leaves behind: a container in a known state, and nothing in it.
///
/// Separate from ``ScenarioSubject`` because a create has no subject yet. Every field that type carries about the item — what the server said about it beforehand, the identity an oracle compares against afterwards, the content it was created with — is a question with no answer before the operation this quadrant is about. Bending ``ScenarioSubject`` to admit an absent item would make `before` optional for all twelve quadrants to serve two of them, and every oracle would then have to ask whether the item it is judging existed when the test began.
///
/// The realization axis says the same thing in the model's own words: a create carries ``ScenarioMatrix/Realization/parent(_:)``, and the state it pins belongs to the container.
///
struct ScenarioCreationSite {
    ///
    /// The container the item is created in, as the server spells it.
    ///
    let parentRemotePath: String

    ///
    /// The container the item is created in, relative to the domain.
    ///
    /// Empty for the domain root, which is the spelling ``CleanRoom/localChildren(of:)`` and ``CleanRoom/localURL(of:)`` expect.
    ///
    let parentLocalPath: String

    ///
    /// Whether this test entered the container while establishing it.
    ///
    /// A record of what the test did rather than of what the container is, which is the honest thing to assert and the only thing available. For a cell pinning the container as dataless this must stay `false` through the operation, and the suites check the enumeration ledger rather than trusting it.
    ///
    let wasEntered: Bool

    ///
    /// Where a named item in this container would be on the server.
    ///
    /// - Parameters:
    ///     - name: The name.
    ///
    /// - Returns: The path.
    ///
    func remotePath(of name: String) -> String {
        parentRemotePath == "/" ? "/\(name)" : "\(parentRemotePath)/\(name)"
    }

    ///
    /// Where a named item in this container would be in the domain.
    ///
    /// - Parameters:
    ///     - name: The name.
    ///
    /// - Returns: The path relative to the domain.
    ///
    func localPath(of name: String) -> String {
        parentLocalPath.isEmpty ? name : "\(parentLocalPath)/\(name)"
    }
}
