// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Where an item sits: how deep, and in what kind of container.
///
/// The two questions are carried in one value because the constraints read them together: which ``RealizationLevel`` a container may be in is decided from the ``Location``, and whether a write is refused is decided from the ``ContainerProfile``. A ``Site`` is then one placement, or the pair a move spans.
///
public struct Placement: Hashable, Sendable, CustomStringConvertible {
    ///
    /// How deep in the domain the item sits.
    ///
    public let location: Location

    ///
    /// The container it sits in, whose kind and permission are already known to be a pairing this harness can build.
    ///
    public let container: ContainerProfile

    ///
    /// Create a placement.
    ///
    /// - Parameters:
    ///     - location: How deep in the domain the item sits.
    ///     - container: The container it sits in.
    ///
    public init(location: Location, container: ContainerProfile) {
        self.location = location
        self.container = container
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the placement in a form which can be read by a human.
    ///
    /// Dense on purpose: this is a part of what ``Scenario`` renders as its own description, which is used as the name of the test case, so it stays short and must not change unless the placement it describes changes.
    ///
    public var description: String {
        let permission = container.permission == .readOnly ? "/ro" : ""

        return "\(container.type.rawValue)\(permission):\(location.rawValue)"
    }
}
