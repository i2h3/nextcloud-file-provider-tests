// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Synchronization
import Testing

///
/// Records a timing so that the run can report it.
///
/// Measurements are attached to the test which took them rather than written to a shared file, so that they travel with the rest of that test's artifacts and cannot be lost when a run is interrupted. The runner collects them afterwards and renders the table.
///
enum MetricsRecorder {
    ///
    /// How many measurements this run has taken.
    ///
    /// Counted here rather than by each suite, because the number that matters is the position within the whole run: it is the run that warms connections and caches, not any one suite.
    ///
    private static let taken = Mutex<Int>(0)

    ///
    /// Record one measurement.
    ///
    /// - Parameters:
    ///     - measurement: What was measured.
    ///     - duration: How long it took.
    ///     - room: The clean room the measurement was taken in.
    ///     - test: The test which took it.
    ///     - payloadSize: The size of the payload involved, where meaningful.
    ///
    static func record(_ measurement: String, duration: Duration, in room: CleanRoom, test: String, payloadSize: Int64? = nil) {
        let ordinal = taken.withLock { count -> Int in
            count += 1

            return count
        }

        let sample = LatencySample(measurement: measurement, duration: duration, server: room.underTest.description, test: test, payloadSize: payloadSize, ordinal: ordinal)

        guard let data = try? JSONEncoder().encode(sample) else {
            return
        }

        Attachment.record(data, named: "\(test).\(measurement.replacingOccurrences(of: " ", with: "-"))\(LatencySample.attachmentSuffix)")
    }
}
