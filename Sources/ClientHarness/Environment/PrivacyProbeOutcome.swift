// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What asking to read a privacy protected location answered.
///
/// Three states rather than two, because the third one is the whole point. A location which is not there answers nothing about whether this process would have been allowed to read it, and a check which reads that as a refusal reports a machine problem to somebody whose machine is fine.
///
public enum PrivacyProbeOutcome: Equatable, Sendable {
    ///
    /// The process may read the location, which it could not do without the privacy grant being probed for.
    ///
    case readable

    ///
    /// The location exists and this process was not allowed to read it.
    ///
    /// - Parameters:
    ///     - code: What the system call reported.
    ///
    case refused(code: Int32)

    ///
    /// There is nothing at the location, so it says nothing about any grant.
    ///
    /// A probe which returns this has expired: the operating system moved or removed what it was written against. That is a fault in this suite and is reported as one.
    ///
    case absent
}
