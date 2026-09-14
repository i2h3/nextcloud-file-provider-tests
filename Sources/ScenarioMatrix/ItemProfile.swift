// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// The item under test: its kind, plus a size when a size is meaningful.
///
/// Carried by a ``Scenario`` as ``Scenario/item``, and the same idea as ``ContainerProfile`` applied to the item rather than to the container it sits in: the two fields are only legal in certain pairings, and the pairing rule lives in the failable initialiser so that an illegal one is unrepresentable rather than merely unlikely.
///
/// The ``Generator`` therefore never restates the rule. It offers ``Constraints/sizes(for:operation:available:)`` to whatever kind it is iterating and skips the combination the initialiser refuses, which keeps the one statement of the rule in one place.
///
public struct ItemProfile: Hashable, Sendable {
    ///
    /// What sort of thing the item is.
    ///
    /// Everything else about the shape of a cell follows from this: which operations are legal on it, and whether ``RealizationLevel/materializedDeep`` is a state it can be in at all.
    ///
    public let kind: ItemKind

    ///
    /// Only present for ``ItemKind/file`` — a directory has no size of its own.
    ///
    /// A ``ItemKind/bundle`` is the case which looks like an exception and is not: it has content, but that content is a tree rather than a byte count, so the upload path it takes is not chosen by a size class.
    ///
    public let size: FileSize?

    ///
    /// Describe the item under test.
    ///
    /// The condition is a biconditional rather than two separate checks, and both directions matter: a file without a size cannot select an upload path, and a directory with one claims a property it does not have. Either would be a cell no harness can build.
    ///
    /// - Parameters:
    ///     - kind: What sort of thing the item is.
    ///     - size: The size class, which must be present exactly when the kind is ``ItemKind/file``.
    ///
    /// - Returns: The profile, or `nil` if a size is present without a file or absent with one.
    ///
    public init?(kind: ItemKind, size: FileSize?) {
        if (kind == .file) != (size != nil) {
            return nil
        }

        self.kind = kind
        self.size = size
    }
}
