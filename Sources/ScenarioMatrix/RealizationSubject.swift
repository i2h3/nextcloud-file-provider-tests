// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Whether a realization level describes the item under test or a container holding it.
///
/// ``Realization`` records which object a given cell's precondition actually describes, and it does so precisely: the item, the one parent a `create` lands in, or the two parents a `move` spans. This enum is the coarser question that comes before that one, and it exists because the menu of plausible ``RealizationLevel`` values is not the same for the two subjects — an item may be ``RealizationLevel/evicted``, while a container may not, since folder eviction is not a state a test can reliably establish.
///
/// ``Constraints/realizationLevels(for:subject:)`` is the only place it is read. ``Generator`` picks the subject from the operation — the item for `metadataUpdate`, `contentUpdate` and `delete`, the container for `create` and `move` — and then filters the returned levels through the matching predicate, ``Constraints/isLegal(itemRealization:origin:operation:kind:)`` or ``Constraints/isLegal(containerRealization:location:)``.
///
public enum RealizationSubject: Hashable, Sendable {
    ///
    /// The item the operation is performed on.
    ///
    /// Selected for the operations that act on something which already exists, and the subject behind ``Realization/item(_:)``. This is the only subject whose levels include ``RealizationLevel/evicted``, which is also the only two-operation history the model admits as a precondition value.
    ///
    case item

    ///
    /// A directory holding the item, whose own state is the precondition.
    ///
    /// Selected where the item under test does not exist yet or moves between containers, and the subject behind ``Realization/parent(_:)`` and ``Realization/parents(source:destination:)``. A container is always a directory, so its levels run from ``RealizationLevel/unknown`` through ``RealizationLevel/materializedDeep`` and are narrowed further by ``Location`` in ``Constraints/isLegal(containerRealization:location:)``.
    ///
    case container
}
