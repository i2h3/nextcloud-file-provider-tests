// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A clean room could not be built.
///
enum CleanRoomError: Error, CustomStringConvertible {
    ///
    /// The client reported that it could not configure the account, so waiting for a domain would be pointless.
    ///
    /// The associated value is the line from the client's own log which says so.
    ///
    case accountSetupFailed(reason: String)

    ///
    /// A second clean room was asked for while one was still standing.
    ///
    case concurrentCleanRoom

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe why a clean room could not be built in a form which can be read by a human.
    ///
    var description: String {
        switch self {
            case let .accountSetupFailed(reason):
                """
                The desktop client refused to configure the account, so no File Provider domain will appear. It reported:
                \(reason)
                """

            case .concurrentCleanRoom:
                """
                Two tests tried to hold a clean room at the same time. There is one desktop client and one File Provider domain on this machine, so tests which share them have to run one after another.

                From the command line the runner passes --no-parallel and this cannot happen. In Xcode, switch parallel execution off: Product, Scheme, Edit Scheme, Test, Options.
                """
        }
    }
}
