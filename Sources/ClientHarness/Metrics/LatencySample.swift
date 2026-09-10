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
    /// Create a measurement.
    ///
    /// - Parameters:
    ///     - measurement: What was measured.
    ///     - duration: How long the measured operation took.
    ///     - server: The server the measurement was taken against.
    ///     - test: The test which took the measurement.
    ///     - payloadSize: The size of the payload involved, where meaningful.
    ///
    public init(measurement: String, duration: Duration, server: String, test: String, payloadSize: Int64? = nil) {
        self.duration = duration
        self.measurement = measurement
        self.payloadSize = payloadSize
        self.server = server
        self.test = test
    }
}
