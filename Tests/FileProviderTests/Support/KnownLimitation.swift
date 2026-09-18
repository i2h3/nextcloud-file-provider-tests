// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ScenarioMatrix
import Testing

///
/// Cells whose subject does not do what the model asks of it, and is not pretending to.
///
/// A cell can fail for three quite different reasons, and only one of them is a defect. It can find a bug; it can be beyond what this harness knows how to establish, which ``ScenarioSelection`` excludes and counts; or the client can be declining the feature outright, deliberately and on the record. That third case has no home in the model — ``ScenarioMatrix/Outcome/rejection`` describes a write refused by a container's permissions, not a capability the client has not shipped.
///
/// **These cells are run rather than excluded**, and that is the whole point of this type. A cell dropped from a run is coverage that disappears silently: the day the feature lands, nothing says the cells exist, nobody remembers to switch them back on, and the feature ships untested. So the cell runs, its failure is registered as expected, and Swift Testing does the remembering — when the client starts doing what the cell asks, `withKnownIssue` reports **expected issue did not occur** and the run fails until somebody removes the entry here.
///
/// That inversion is the design. Coverage cannot be lost by forgetting; it can only be lost by editing this file, which is a deliberate act with a reason attached.
///
enum KnownLimitation {
    ///
    /// Why this cell is expected to fail, if it is.
    ///
    /// - Parameters:
    ///     - cell: The cell's description.
    ///
    /// - Returns: The reason, or `nil` where the cell is expected to hold.
    ///
    static func reason(for cell: String) -> Comment? {
        guard cell.contains("kind:bundle") else {
            return nil
        }

        // Not every operation on a package is refused, which the first run of these cells established by failing this expectation rather than the cell: deleting a package the client has never downloaded reaches the server like any other deletion, in all four of its cells. Only a package the client holds locally is in the ignore list, and only those deletions are dropped.
        //
        // Narrowed to what was measured rather than to what the log line sounded like. The wording — "Refusing to sync bundle or package" — reads as though it covers everything, and it does not.
        guard !(cell.contains(" delete ") && cell.contains("item:dataless")) else {
            return nil
        }

        return """
        The client does not synchronise packages it holds locally, deliberately and in both directions. Its extension says so in its own log — "Refusing to sync bundle or package because this is not supported" — then adds the name to an ignore list and reports the exclusion to the main app over XPC. Measured on 2026-09-17: a package created in the client never reaches the server, a rename of one never leaves the Mac, and deleting one the client has downloaded is dropped — while deleting one it has never downloaded works, which is why that case is not expected to fail.

        Disabled by https://github.com/nextcloud/desktop/pull/9971; restoring it is tracked by https://github.com/nextcloud/desktop/issues/9827. When it lands, these cells stop failing and this expectation becomes the thing that fails — which is how the suite tells somebody to delete this entry rather than leaving ninety-three cells quietly untested.
        """
    }
}
