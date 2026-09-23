// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What reading one of the File Provider extension's switches found.
///
/// Three states rather than two, for the same reason ``PrivacyProbeOutcome`` has three: "it is not set" and "I could not find out" are different answers, and a harness which returns `false` for both will one day report a machine as untouched while it is blocked.
///
/// That is not hypothetical here. macOS 27 put the client's application data behind a grant of its own, and a run on a machine without it reads every one of these switches as absent. The switch this matters most for is the one which stops the client synchronising: ``ClientSynchronisation/unblock()`` confirms its own work by reading the switch back, and with two states a read which could not happen confirmed it.
///
enum ExtensionDefaultState: Equatable, Sendable {
    ///
    /// The switch is present and reads as on.
    ///
    case on

    ///
    /// The switch is absent, or present and reading as off.
    ///
    /// Absent and off are deliberately one state. The extension treats them the same, and the harness removes a switch rather than writing `false` precisely so that a machine which was put back is indistinguishable from one which was never touched.
    ///
    case off

    ///
    /// The switch could not be read, so nothing is known about it, and what `defaults` said instead.
    ///
    /// Distinct from ``off`` because acting on it is different: a caller confirming that it cleared something has not confirmed anything, and a caller merely asking whether a machine is blocked can reasonably carry on.
    ///
    /// It carries the complaint because the first time this fired nobody could say why. The harness had the answer — an exit status and two streams — and reported only that something had gone wrong, which is the same defect as a timeout naming what did not appear and not what was there. Whatever comes back here belongs in the message a person reads.
    ///
    case unreadable(String)
}
