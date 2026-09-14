// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// The ``Origin`` × ``Operation`` pair that forms the suite spine.
///
/// Tests are grouped by quadrant because that is how a failure is described in practice — "a remote move is broken" — and because the oracle direction, local→server versus server→local, is fixed per quadrant.
///
/// It is therefore the coordinate the rest of the model is addressed by: ``Generator/scenarios(for:phase:)`` takes one and returns the rows it contains, ``Generator/matrix(for:)`` uses it as the key it groups by, and one quadrant becomes one suite — `RemoteMetadataUpdateTests` runs the cells of `Quadrant(origin: .remote, operation: .metadataUpdate)` and nothing else.
///
public struct Quadrant: Hashable, Sendable, CaseIterable {
    ///
    /// Where the change came from.
    ///
    /// One half of the pair, and the half which fixes what the oracles compare against what: a ``Origin/local`` change is expected to reach the server, a ``Origin/remote`` one to reach this Mac, and a ``Origin/concurrent`` one is the conflict case where both sides moved at once.
    ///
    public let origin: Origin

    ///
    /// What was done to the item.
    ///
    /// The other half of the pair. Together with ``origin`` it decides whether the quadrant can hold any cells at all — see ``allCases`` — and, once it does, how the remaining axes of a ``Scenario`` are read, because ``Operation/move`` carries a pair of placements and a pair of parent realization levels where every other operation carries one of each.
    ///
    public let operation: Operation

    ///
    /// Name one quadrant of the matrix.
    ///
    /// Nothing is rejected here, because an illegal pair is still a perfectly well-formed coordinate: ``Constraints/isLegal(_:)`` answers whether it can hold cells, and ``Generator/scenarios(for:phase:)`` returns nothing for one that cannot.
    ///
    /// - Parameters:
    ///     - origin: Where the change came from.
    ///     - operation: What was done to the item.
    ///
    public init(origin: Origin, operation: Operation) {
        self.origin = origin
        self.operation = operation
    }

    ///
    /// Every quadrant that can legally contain cases.
    ///
    /// The Cartesian product of ``Origin`` and ``Operation`` filtered through ``Constraints/isLegal(_:)``, which is why the two conflict quadrants that cannot exist — a ``Origin/concurrent`` ``Operation/create`` and a ``Origin/concurrent`` ``Operation/move`` — are absent rather than present and empty. That is the same rule the whole model follows: an impossible combination is never emitted, so a suite full of skips never reads as coverage it does not have.
    ///
    public static var allCases: [Quadrant] {
        Origin.allCases.flatMap { origin in
            Operation.allCases.compactMap { operation in
                let quadrant = Quadrant(origin: origin, operation: operation)

                return Constraints.isLegal(quadrant) ? quadrant : nil
            }
        }
    }

    ///
    /// The quadrant written as one camel-cased identifier, such as `RemoteMetadataUpdate`.
    ///
    /// This is the human-facing name of the group: it is what a suite covering the quadrant is called, and what a heading over its rows says. Built from the raw values of the two axes with `String.capitalizedFirst`, the helper next door in `String+CapitalizedFirst.swift`, which upper-cases only the first character so that the camel case of a value like `metadataUpdate` survives into the name.
    ///
    /// Unlike ``Scenario/description`` this names a whole group rather than a row, so it identifies a suite and never a single test case.
    ///
    public var name: String {
        "\(origin.rawValue.capitalizedFirst)\(operation.rawValue.capitalizedFirst)"
    }
}
