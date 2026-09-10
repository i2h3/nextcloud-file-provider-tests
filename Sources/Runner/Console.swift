// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Writes progress to the terminal, immediately.
///
/// A run deploys containers and waits for domains for minutes at a time. Standard output is block buffered whenever it is not a terminal — which is the case in continuous integration and whenever the output is piped — so without an explicit flush the whole run would appear to hang and then print everything at once. Every line the runner emits therefore goes through here.
///
enum Console {
    ///
    /// Write a line and flush it.
    ///
    /// - Parameters:
    ///     - message: The line to write.
    ///
    static func log(_ message: String = "") {
        print(message)
        fflush(stdout)
    }

    ///
    /// Write a question and flush it, leaving the cursor on the same line.
    ///
    /// - Parameters:
    ///     - message: The question to write.
    ///
    static func ask(_ message: String) {
        print(message, terminator: "")
        fflush(stdout)
    }
}
