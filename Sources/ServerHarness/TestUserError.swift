// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A problem provisioning the user of a test.
///
public enum TestUserError: Error, Equatable, CustomStringConvertible {
    ///
    /// The server did not issue an app password for a freshly created user.
    ///
    case appPasswordNotIssued(user: String, reason: String)

    public var description: String {
        switch self {
            case let .appPasswordNotIssued(user, reason):
                "The server issued no app password for \"\(user)\": \(reason)"
        }
    }
}
