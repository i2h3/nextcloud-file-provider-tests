// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// The trait gating the suites which measure how often something happens rather than whether it happened.
///
/// Characterisation is a different activity from testing, and mixing the two costs both. A contract test asks whether the client did the right thing and answers yes or no; a characterisation suite runs the same thing dozens of times and answers with a rate, which takes far longer and fails nothing. Putting that behind its own switch keeps an ordinary run the length it is, and keeps a rate from being quoted off a single sample.
///
extension Trait where Self == ConditionTrait {
    ///
    /// Enable the suite only when a run asked for repeated trials.
    ///
    static var requiresRepetitions: Self {
        .enabled(if: RunEnvironment.repetitions() != nil, "Characterisation is off. Set \(RunEnvironment.repetitionsVariableName) to the number of trials to run it.")
    }
}
