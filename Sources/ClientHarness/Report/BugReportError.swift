// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A draft report could not be written.
///
public enum BugReportError: Error, Equatable, CustomStringConvertible {
    ///
    /// The reports would have gone somewhere the repository could pick them up.
    ///
    /// A draft describes a defect which has not been reported to anyone yet, and this repository is public. Writing one where it could be committed is the one mistake here which cannot be taken back, because a commit outlives the file it added.
    ///
    case wouldBeCommittable(path: String)

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        switch self {
            case let .wouldBeCommittable(path):
                "Refusing to draft reports at \(path), because the repository does not ignore it. A draft describes a defect nobody has reported yet and this repository is public. Write them under the artifacts directory, which is ignored."
        }
    }
}
