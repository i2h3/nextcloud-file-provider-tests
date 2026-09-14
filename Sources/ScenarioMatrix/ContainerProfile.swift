// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// A container the matrix can place an item in. Invalid pairings are unrepresentable via ``init(type:permission:)``.
///
/// That unrepresentability is the point of the type. Left as two free axes, ``ContainerType`` and ``Permission`` would cross into a cell for a folder the test user owns and may not write to, and every place which crosses them would have to remember the rule that skips it. Here there is no way to make a profile except through a failable initialiser which refuses that pairing, so the illegal combination cannot be written down at all and nothing downstream needs a rule against it.
///
/// A profile is one half of a ``Placement``, the other being the ``Location``. Which profiles a run may use at all comes from ``Phase/containers``, which yields ``standard`` alone until shared and group containers become constructible.
///
public struct ContainerProfile: Hashable, Sendable {
    ///
    /// What kind of container this is.
    ///
    public let type: ContainerType

    ///
    /// Whether the test user may write into it.
    ///
    public let permission: Permission

    ///
    /// Returns `nil` for combinations this harness cannot construct.
    ///
    /// Note the precise claim, which was corrected after a sibling project refuted the earlier one: a read-only folder you own **does exist** on a real server — `chmod 0555` plus `occ files:scan` drops it to `oc:permissions RG`, writes return 403, and it is fully reversible.
    ///
    /// What rules it out here is the harness's own decision to reach server state over HTTP only: both halves of that recipe need container-level command execution. So this is a *constructability* limit, not an impossibility, and it becomes representable the moment that decision changes.
    ///
    /// - Parameters:
    ///     - type: What kind of container it is.
    ///     - permission: Whether the test user may write into it.
    ///
    /// - Returns: The profile, or `nil` for a pairing this harness cannot construct.
    ///
    public init?(type: ContainerType, permission: Permission) {
        if type == .standard, permission == .readOnly {
            return nil
        }

        self.type = type
        self.permission = permission
    }

    ///
    /// The plain folder every run has: owned by the test user, and writable by them.
    ///
    /// The one profile ``Phase/a`` offers, and the baseline the others are read against. Force-unwrapping is safe by construction, because ``ContainerType/standard`` with ``Permission/readWrite`` is exactly the pairing ``init(type:permission:)`` accepts.
    ///
    public static let standard = ContainerProfile(type: .standard, permission: .readWrite)!

    ///
    /// Whether a write into this container is expected to be refused.
    ///
    /// A cell whose ``Site`` touches such a container expects ``Outcome/rejection`` rather than convergence, and a move is refused by either end, since it must remove from the source *and* create in the destination.
    ///
    public var rejectsWrites: Bool {
        permission == .readOnly
    }
}
