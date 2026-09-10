// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A live suite was reached without an environment describing a run.
///
enum LiveEnvironmentError: Error, CustomStringConvertible {
    ///
    /// No environment describing a run is present.
    ///
    case absent

    var description: String {
        "This suite needs servers to run against. Start it through `swift run tests` instead of `swift test`."
    }
}
