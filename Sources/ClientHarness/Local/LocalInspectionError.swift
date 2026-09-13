// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The file system would not say what is at a location.
///
/// Distinct from there being nothing there, which is an answer and is reported as `nil`. This is the absence of an answer, and the two have been conflated in this project before with expensive results: a refused read rendered as an empty directory is the difference between a client which has not populated a domain yet and a machine which was never allowed to look, and the suite spent a day on the wrong one.
///
/// The same distinction is made one layer up, by the preflight checks, which separate granted from denied from never-asked. A preflight which distinguishes four states sitting on top of a primitive which distinguishes one is a preflight whose answer is thrown away immediately below it.
///
public struct LocalInspectionError: Error, Equatable, CustomStringConvertible {
    ///
    /// The location which could not be described.
    ///
    public let path: String

    ///
    /// What the system call reported.
    ///
    public let code: Int32

    ///
    /// Whether the refusal is a matter of permission rather than of the file system.
    ///
    /// `EPERM` and `EACCES` are what a privacy refusal looks like from here, and they are worth naming separately because the remedy is a person granting something rather than anything the suite can do.
    ///
    public var isRefusal: Bool {
        code == EPERM || code == EACCES
    }

    ///
    /// Describe a location which could not be inspected.
    ///
    /// - Parameters:
    ///     - path: The location.
    ///     - code: What the system call reported.
    ///
    public init(path: String, code: Int32) {
        self.code = code
        self.path = path
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        let reason = String(cString: strerror(code))

        guard isRefusal else {
            return "\"\(path)\" could not be inspected: \(reason). This is not the same as nothing being there."
        }

        return "\"\(path)\" could not be inspected because the process was refused: \(reason). Full Disk Access for the application starting the run is what this usually means, and nothing below this point knows anything about what is or is not at that location."
    }
}
