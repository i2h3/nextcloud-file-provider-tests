// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation

///
/// Turns the timings the tests recorded into a table.
///
/// This is the only custom reporting in the suite, and it exists because it is the only thing the standard artifacts cannot express. Results themselves are reported as JUnit XML, which most report viewers render and which Xcode does not need at all; a synchronisation which became four times slower while still passing is invisible there.
///
public enum MetricsSummary {
    ///
    /// Collect every measurement written during a run.
    ///
    /// - Parameters:
    ///     - directory: The attachments directory of the run.
    ///
    /// - Returns: The measurements, in the order they were found.
    ///
    public static func samples(in directory: URL) -> [LatencySample] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        var samples = [LatencySample]()

        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(LatencySample.attachmentSuffix) {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }

            if let sample = try? decoder.decode(LatencySample.self, from: data) {
                samples.append(sample)

                continue
            }

            if let batch = try? decoder.decode([LatencySample].self, from: data) {
                samples.append(contentsOf: batch)
            }
        }

        return samples
    }

    ///
    /// Render measurements as a Markdown table.
    ///
    /// - Parameters:
    ///     - samples: The measurements to render.
    ///
    /// - Returns: The table, or a note if there is nothing to show.
    ///
    public static func render(_ samples: [LatencySample]) -> String {
        guard !samples.isEmpty else {
            return "No measurements were recorded during this run."
        }

        var lines = [
            "| Measurement | Server | Test | Duration | Payload |",
            "| --- | --- | --- | ---: | ---: |",
        ]

        for sample in samples.sorted(by: { ($0.measurement, $0.server, $0.test) < ($1.measurement, $1.server, $1.test) }) {
            let payload = sample.payloadSize.map { "\($0) B" } ?? "—"
            lines.append("| \(sample.measurement) | \(sample.server) | \(sample.test) | \(format(sample.duration)) | \(payload) |")
        }

        return lines.joined(separator: "\n")
    }

    ///
    /// Format a duration for the table.
    ///
    /// - Parameters:
    ///     - duration: The duration to format.
    ///
    /// - Returns: The formatted duration in seconds.
    ///
    private static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

        return String(format: "%.3f s", seconds)
    }
}
