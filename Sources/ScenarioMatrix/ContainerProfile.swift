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
    /// A read-only folder you own **does exist** on a real server, and the recipe works. Measured on `nextcloud:34.0.0` and again on `nextcloud:35.0.1`, which is what `latest` resolves to: `chmod -R a-w` on the folder inside the container, followed by `occ files:scan --path=/<user>/files/<folder>`, and a `PUT` of a new file, an `MKCOL`, a `DELETE` of a child and a `MOVE` in either direction all answer 403.
    ///
    /// Three details of that recipe were wrong here until they were measured, and each would have cost a day. The folder reports `oc:permissions RGDN`, not `RG` — `RG` is what the *child* drops to. `chmod 0555` on the folder alone is not enough, because an overwrite of an existing child still succeeds, which is why the mode has to be applied recursively. And the scan is not cosmetic: without it writes already fail with 403 while `oc:permissions` still advertises `RGDNVCK`, so the server reports a folder as writable that it will refuse to write — and the client decides what to offer from exactly that property.
    ///
    /// The earlier reason given here — that the harness reaches server state over HTTP only — was already false when it was written. `TrashApplication` runs `occ` against the container once per room, `TestUser` provisions and deletes through the container manager, and `ServerWorkspace` pauses and resumes the container itself.
    ///
    /// What rules the pairing out is narrower and harder, and it is about observing rather than establishing. Nothing in this harness reads ``rejectsWrites`` — its only caller is the generator — so a container the model calls rejecting would be built writable, and the cell would assert the opposite of its own premise and pass. ``Outcome/rejection`` has no judge, and ``OracleClause/sharePermission``, the one clause that makes a refusal correct, has no implementation. Beyond that, more than half of the cells such a profile would emit place the rejecting container at the domain **root**, which this recipe cannot build: the root is the directory every fixture is uploaded into and the directory the domain mounts on. And `occ user:delete` reports success while leaving a home directory containing a read-only folder on disk, so a run would leak into a container the rest of the suite shares.
    ///
    /// So this stays a *constructability* limit rather than an impossibility. What has to exist first is a judge for a refusal, not a way to cause one.
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
