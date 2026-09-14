// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import ScenarioMatrix
import Testing

///
/// Lets a cell name itself in a test run, and name itself the same way every time.
///
/// The description a scenario already carries is its identity — `remote metadataUpdate item:dataless kind:file size:small at:standard:root` — and it is stable by construction, because the model pins it with a snapshot test. Encoding the argument as that string rather than as its fields means a failure names the cell in the run output, in the artifacts and in a drafted report using one spelling, which is what makes a failure traceable back to the row it came from.
///
extension Scenario: CustomTestArgumentEncodable {
    ///
    /// Implementation for `CustomTestArgumentEncodable` conformance.
    ///
    /// - Parameters:
    ///     - encoder: The encoder to write to.
    ///
    /// - Throws: Whatever encoding raises.
    ///
    public func encodeTestArgument(to encoder: some Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(description)
    }
}
