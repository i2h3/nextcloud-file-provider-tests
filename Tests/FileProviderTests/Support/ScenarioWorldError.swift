// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A cell's world could not be built.
///
/// Raised from the world builder rather than from an expectation, and raised rather than skipped. A cell whose precondition could not be established has made no measurement, and the difference between that and a contradicted expectation is the difference between a harness problem and a client defect. Silently passing such a cell would be worse than either.
///
/// It carries the step it failed at because a bare error from the world builder is close to useless. The first run of the generated suite failed one cell in twelve with `Not found.`, which named neither what was being done nor to what — the same shortcoming that made an unattributed `NSCocoaErrorDomain 513` cost this project a day. Building a world takes a dozen steps against two machines, and the step is most of the answer.
///
struct ScenarioWorldError: Error, CustomStringConvertible {
    ///
    /// What could not be done, phrased to complete the sentence "this harness cannot establish …" or to name the step which failed.
    ///
    let subject: String

    ///
    /// Whatever the file system, the server or the waiting raised, where there was one.
    ///
    let underlying: (any Error)?

    ///
    /// Describe a state this harness cannot put a real client and server into.
    ///
    /// - Parameters:
    ///     - subject: What could not be established, phrased to complete the sentence "this harness cannot establish …".
    ///
    /// - Returns: The error.
    ///
    static func unsupported(_ subject: String) -> ScenarioWorldError {
        ScenarioWorldError(subject: subject, underlying: nil)
    }

    ///
    /// Describe a step of world building which failed.
    ///
    /// - Parameters:
    ///     - step: What was being done, phrased to complete the sentence "while …".
    ///     - error: What was raised.
    ///
    /// - Returns: The error.
    ///
    static func failed(_ step: String, _ error: any Error) -> ScenarioWorldError {
        ScenarioWorldError(subject: step, underlying: error)
    }

    ///
    /// Run a step of world building, and attribute whatever it raises to that step.
    ///
    /// A ``ScenarioWorldError`` raised inside passes through unchanged, so a nested step keeps the name it already has rather than being relabelled by its caller.
    ///
    /// - Parameters:
    ///     - step: What is being done, phrased to complete the sentence "while …".
    ///     - work: The step.
    ///
    /// - Returns: Whatever the step returns.
    ///
    /// - Throws: ``ScenarioWorldError`` naming the step.
    ///
    static func doing<T>(_ step: String, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as ScenarioWorldError {
            throw error
        } catch {
            throw failed(step, error)
        }
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    var description: String {
        guard let underlying else {
            return "This harness cannot establish \(subject). The cell was not measured, and nothing about the client follows from it."
        }

        return "The cell's world could not be built: it failed while \(subject), with \(underlying). The cell was not measured, and nothing about the client follows from it."
    }
}
