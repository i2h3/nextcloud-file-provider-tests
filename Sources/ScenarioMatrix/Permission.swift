// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Write permission on the container.
///
/// Only varies inside shared and group containers; a user's own folder is always read-write, which is why this is a conditional sub-axis rather than a top-level one.
///
/// It is paired with a ``ContainerType`` into a ``ContainerProfile``, which is where that conditionality is enforced rather than merely described. This axis is also what makes a matrix cell three-valued instead of pass-or-fail: a write into a container that does not grant it is expected to end in ``Outcome/rejection``, which is a correct result and not a defect to be reported.
///
public enum Permission: String, CaseIterable, Hashable, Sendable {
    ///
    /// The test user may read and write.
    ///
    /// The only permission a ``ContainerType/standard`` container can carry, and the only one a ``Phase/a`` run offers at all.
    ///
    case readWrite

    ///
    /// The test user may read but not write, as a share or a group folder granted without write permission.
    ///
    /// ``ContainerProfile/rejectsWrites`` is how a cell finds out, and a refusal is decided by permission *before* the bytes, the realization state or the pin can matter. That is why expected-rejection cells are collapsed to one representative per equivalence class instead of being enumerated across every other axis.
    ///
    case readOnly
}
