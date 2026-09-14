// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One measurement worth watching across releases.
///
/// Pass or fail says nothing about a synchronisation which became four times slower but still finished inside its timeout. Tests therefore record their timings as samples, the run writes them out as JSON, and the runner turns the collection into a table. This is the part of a run which JUnit cannot express, and the only reason any custom reporting exists at all.
///
public struct LatencySample: Codable, Hashable, Sendable {
    ///
    /// The file name suffix marking an attachment which holds measurements.
    ///
    /// The tests write measurements as attachments and the runner collects them afterwards, so both sides have to agree on how to recognise one. The constant lives here, next to the value it describes, because the two targets share nothing else.
    ///
    public static let attachmentSuffix = ".latency.json"

    ///
    /// How long the measured operation took.
    ///
    public let duration: Duration

    ///
    /// What was measured, for example `server-to-local propagation`.
    ///
    public let measurement: String

    ///
    /// The size of the payload involved, in bytes, where that is meaningful.
    ///
    public let payloadSize: Int64?

    ///
    /// The server the measurement was taken against, as ``ServerUnderTest/description`` spells it.
    ///
    public let server: String

    ///
    /// The test which took the measurement.
    ///
    public let test: String

    ///
    /// Where this measurement fell in the run, counting from one.
    ///
    /// Recorded because a suite whose cases are generated runs them in a fixed order, and a fixed order puts some axis in perfect correlation with time. The first cells of a run pay for connections being opened and caches being cold, and without the position that cost is indistinguishable from an effect of whichever axis value happened to be sorted first.
    ///
    /// This project has the example. The first measured comparison of the push backend showed deletions of dataless items arriving in 1.57 seconds against 0.83 for materialized ones — which reads as a finding about realization, and cannot be, because every dataless cell ran before every materialized one and the later group's spread was twenty times tighter. With the position recorded, that confound is visible in the data rather than resting on somebody remembering the sort order.
    ///
    public let ordinal: Int?

    ///
    /// Create a measurement.
    ///
    /// - Parameters:
    ///     - measurement: What was measured.
    ///     - duration: How long the measured operation took.
    ///     - server: The server the measurement was taken against.
    ///     - test: The test which took the measurement.
    ///     - payloadSize: The size of the payload involved, where meaningful.
    ///     - ordinal: Where the measurement fell in the run, counting from one.
    ///
    public init(measurement: String, duration: Duration, server: String, test: String, payloadSize: Int64? = nil, ordinal: Int? = nil) {
        self.duration = duration
        self.ordinal = ordinal
        self.measurement = measurement
        self.payloadSize = payloadSize
        self.server = server
        self.test = test
    }
}
