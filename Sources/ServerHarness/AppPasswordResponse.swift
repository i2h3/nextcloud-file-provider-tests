// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The answer of the endpoint which issues an app password.
///
/// Rainmaker can revoke an app password but does not request one, so the one request needed here is made directly with Rainmaker's own request builder and decoded into this type.
///
struct AppPasswordResponse: Decodable {
    ///
    /// The envelope every OCS answer is wrapped in.
    ///
    struct Envelope: Decodable {
        ///
        /// The payload of the answer.
        ///
        let data: Payload
    }

    ///
    /// The payload of an answer issuing an app password.
    ///
    struct Payload: Decodable {
        ///
        /// The issued app password.
        ///
        let apppassword: String
    }

    ///
    /// The envelope of the answer.
    ///
    let ocs: Envelope
}
