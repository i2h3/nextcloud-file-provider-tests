// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``LogExcerpt`` and ``ExtensionLogEntry``.
///
/// A clean room leaves a few hundred lines behind and a report can carry a few dozen. The rule which chooses between them has to work without understanding the defect, so what is pinned here is that it leans on what the test already said, that it never drops anything silently, and that the two traps in real logs are handled.
///
@Suite("Log excerpt")
struct LogExcerptTests {
    ///
    /// The zone the machine wrote its log in, which the log itself does not say.
    ///
    static let timeZone = TimeZone(identifier: "UTC")!

    ///
    /// Write one line the way the extension writes them.
    ///
    /// - Parameters:
    ///     - message: What it said.
    ///     - level: How important it considered it.
    ///     - second: Which second of the minute it was written in.
    ///     - details: Whatever it was about.
    ///
    /// - Returns: The line.
    ///
    static func line(_ message: String, level: String = "debug", second: Int = 0, details: [String: String] = [:]) -> String {
        let described = details.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")

        return #"{"category":"Enumerator","date":"2026.09.11 12:00:\#(String(format: "%02d", second)).000","details":{\#(described)},"level":"\#(level)","message":"\#(message)"}"#
    }

    ///
    /// Read lines the way a report does.
    ///
    /// - Parameters:
    ///     - lines: The lines.
    ///
    /// - Returns: The entries.
    ///
    static func parse(_ lines: [String]) -> [ExtensionLogEntry] {
        lines.compactMap { ExtensionLogEntry.parse($0, timeZone: timeZone) }
    }

    @Test
    func `A line is read into its parts.`() throws {
        let entry = try #require(ExtensionLogEntry.parse(Self.line("Something happened.", level: "info", details: ["name": "contested.bin"]), timeZone: Self.timeZone))

        #expect(entry.message == "Something happened.")
        #expect(entry.level == "info")
        #expect(entry.details["name"] == "contested.bin")
        #expect(entry.date != nil)
    }

    @Test
    func `A line which is not one is skipped rather than thrown.`() {
        #expect(ExtensionLogEntry.parse("not json at all", timeZone: Self.timeZone) == nil)
        #expect(Self.parse(["{}", "also not json", Self.line("Kept.")]).count == 1)
    }

    ///
    /// The trap in a real log. The extension writes this value when it was asked to log an error and there was none, so a rule which treats the presence of an error as trouble selects exactly the lines which say nothing went wrong.
    ///
    @Test
    func `An absent error is not mistaken for an error.`() throws {
        let absent = try #require(ExtensionLogEntry.parse(Self.line("Nothing wrong.", details: ["error": ExtensionLogEntry.absentErrorSentinel]), timeZone: Self.timeZone))
        let real = try #require(ExtensionLogEntry.parse(Self.line("Something wrong.", details: ["error": "the server refused"]), timeZone: Self.timeZone))

        #expect(!absent.reportsError)
        #expect(real.reportsError)
    }

    ///
    /// The strongest signal available, and an entirely mechanical one: the failing expectation named a file, so the lines about that file are the ones to keep.
    ///
    @Test
    func `Lines about what the test was about are kept ahead of the rest.`() {
        var lines = (1 ... 50).map { Self.line("Routine number \($0).") }
        lines.append(Self.line("Uploaded it.", details: ["name": "contested.bin"]))

        let selected = LogExcerpt.select(from: Self.parse(lines), failedAt: nil, subjects: ["contested.bin"], limit: 5)

        #expect(selected.lines.contains { $0.message == "Uploaded it." })
        #expect(selected.lines.count == 5)
        #expect(selected.omitted == 46)
    }

    ///
    /// Enumeration repeats itself, and a budget spent on the same sentence forty times says nothing more than spending it once.
    ///
    @Test
    func `Repetition is marked rather than repeated.`() {
        let selected = LogExcerpt.select(from: Self.parse(Array(repeating: Self.line("Again."), count: 6)), failedAt: nil, subjects: [], limit: 40)

        #expect(selected.lines.count == 1)
        #expect(selected.lines.first?.message == "Again. (× 6)")
    }

    @Test
    func `Nothing is left out without saying so.`() {
        let selected = LogExcerpt.select(from: Self.parse((1 ... 30).map { Self.line("Line \($0).") }), failedAt: nil, subjects: [], limit: 10)

        #expect(selected.lines.count == 10)
        #expect(selected.omitted == 20)
    }

    @Test
    func `A log which fits is kept whole and in order.`() {
        let selected = LogExcerpt.select(from: Self.parse((1 ... 5).map { Self.line("Line \($0).") }), failedAt: nil, subjects: [], limit: 40)

        #expect(selected.omitted == 0)
        #expect(selected.lines.map(\.message) == (1 ... 5).map { "Line \($0)." })
    }

    ///
    /// Only what happened before a failure can have caused it, so the window is asymmetric.
    ///
    @Test
    func `Only what happened around the failure is considered.`() throws {
        let entries = Self.parse((0 ... 50).map { Self.line("Second \($0).", second: min($0, 59)) })
        let failedAt = try #require(entries.last?.date)

        let selected = LogExcerpt.select(from: entries, failedAt: failedAt, subjects: [], limit: 100)

        #expect(!selected.lines.isEmpty)
    }

    ///
    /// The failure mode which matters most. If the recorded zone is wrong, or a clock moved, the window would hold nothing — and an empty Evidence section reads as "nothing happened" rather than as "this was not found".
    ///
    @Test
    func `A window which finds nothing widens rather than reporting silence.`() {
        let entries = Self.parse((1 ... 5).map { Self.line("Line \($0).") })
        let selected = LogExcerpt.select(from: entries, failedAt: Date(timeIntervalSince1970: 0), subjects: [], limit: 40)

        #expect(selected.lines.count == 5)
    }

    @Test
    func `An empty log yields an empty excerpt rather than failing.`() {
        let selected = LogExcerpt.select(from: [], failedAt: Date(), subjects: ["x"], limit: 40)

        #expect(selected.lines.isEmpty)
        #expect(selected.omitted == 0)
    }
}
