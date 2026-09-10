// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A problem deploying or preparing a server.
///
public enum ManagedServerError: Error, Equatable, CustomStringConvertible {
    ///
    /// The address of a deployed container could not be formed from its port.
    ///
    case addressNotFormable(port: UInt)

    public var description: String {
        switch self {
            case let .addressNotFormable(port):
                "Failed to form a server address for the container port \(port)."
        }
    }
}
