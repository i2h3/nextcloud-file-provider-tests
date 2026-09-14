// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// What kind of container the item lives in.
///
/// One of the two halves of a ``ContainerProfile``, the other being ``Permission``. That these are mutually exclusive values of one axis rather than three booleans is one of the two collapses the whole axis model rests on: an item lives in exactly one kind of container, and "standard and shared at once" is then not a state anybody has to prune away later.
///
/// The kind of a container changes more than who may write into it. A ``Site`` whose placements are not all ``standard`` earns the ``Oracle/sharePermission`` clause, and a move between two different kinds is copy and delete on the server rather than a rename — which is what ``Site/crossesContainerType`` reports to the ``Oracle/moveIdentity`` clause.
///
public enum ContainerType: String, CaseIterable, Hashable, Sendable {
    ///
    /// A plain folder owned by the test user. Always full-permission.
    ///
    /// The only kind a ``Phase/a`` run can build, and the reason ``ContainerProfile/init(type:permission:)`` refuses to pair it with ``Permission/readOnly``.
    ///
    case standard

    ///
    /// A folder shared *in* by another Nextcloud user.
    ///
    /// Available from ``Phase/b``, which waits on the server-side library gaining the OCS Sharing and OCS Provisioning APIs needed to create the second user and the share.
    ///
    case shared

    ///
    /// A folder from the `groupfolders` app.
    ///
    /// Also gated on ``Phase/b``, and kept apart from ``shared`` because a group folder is mounted by an app rather than by a share, so its permissions and its identity on the server are established along a different path and can fail independently.
    ///
    case groupfolder
}
