// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Whether the **server** keeps deleted items.
///
/// Only meaningful for `delete`, and realised as two server profiles rather than a per-case toggle.
///
/// Grounding corrected after measurement: this is NOT `NSFileProviderDomain.supportsSyncingTrash`. That property is settable only by the provider's own app, and the Nextcloud client sets it **YES unconditionally on every domain it creates** (`fileproviderdomainmanager.mm:355`, `:412`), so `NO` is a state no real client ever presents and modelling it would produce cells that cannot be constructed.
///
/// What is real is the server capability: the shipped extension genuinely branches on `capabilities.files.undelete`, and `files_trashbin` can be disabled in about two seconds. So ``without`` means *the server has no trash bin*, established per server profile and verified by reading the capability back — never inferred from the domain flag.
///
/// The gate is ``Constraints/trashValues(for:available:)``, which hands back `nil` for every operation but ``Operation/delete``, so ``Scenario/trash`` is absent everywhere else. Where it is present it decides how tightly ``Oracle/trashPlacement`` may be asserted, which the ``Generator`` turns into a ``Contract``.
///
public enum TrashSupport: String, CaseIterable, Hashable, Sendable {
    ///
    /// The server keeps deleted items, so a deletion has a destination worth asserting.
    ///
    /// The ``Oracle/trashPlacement`` clause is ``Contract/determined`` here: the item is gone from the domain and present in the server's trash bin, and both halves may be checked.
    ///
    case with

    ///
    /// The server has no trash bin, because `files_trashbin` is disabled on this profile.
    ///
    /// The deletion still has to leave the domain, but where the item ends up is explicitly not guaranteed by API contract, so the ``Oracle/trashPlacement`` clause becomes ``Contract/underdetermined(permitting:because:)`` and only the common invariant may be asserted. Asserting a destination here would be testing an implementation detail the specification deliberately leaves open.
    ///
    case without
}
