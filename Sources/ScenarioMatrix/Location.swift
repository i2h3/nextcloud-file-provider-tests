// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Depth of the item within the domain.
///
/// One half of a ``Placement``, the other being the ``ContainerProfile`` the item sits in. Depth is not decoration here: it decides which ``RealizationLevel`` a container can legally be in, because the domain root is enumerated as soon as the domain mounts and every container this model can place therefore sits directly beneath something already enumerated.
///
/// There are deliberately only two values. A third, deeper one is what it would take to reach a genuinely ``RealizationLevel/unknown`` container, and that is deferred rather than assumed: creating into `domain/a/b` performs a path lookup through `a`, which may itself enumerate.
///
public enum Location: String, CaseIterable, Hashable, Sendable {
    ///
    /// Directly in the domain root, which is always enumerated once the domain mounts.
    ///
    /// Only ``RealizationLevel/materialized`` is therefore a legal container state here, and ``ContentPolicy/pinnedInherited`` is ruled out, since an item in the root has no ancestor below the domain to inherit a pin from.
    ///
    case root

    ///
    /// Inside a folder below the domain root.
    ///
    /// The value that makes the interesting preconditions reachable: a container one level down is ``RealizationLevel/dataless`` at t=0 and can be driven from there, and there is an ancestor for ``ContentPolicy/pinnedInherited`` to inherit from.
    ///
    case subdirectory
}
