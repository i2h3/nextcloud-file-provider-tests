// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``JUnitReader``.
///
/// Only the question of whether anything ran is pinned here, and it is pinned because the previous answer was a substring search which a toolchain change quietly inverted: three green runs in a row ended in an error saying that no test had matched the filter. The check lives in this target rather than in the runner so that it can be tested at all.
///
@Suite("xUnit report")
struct JUnitReaderTests {
    ///
    /// Write a report and read it back.
    ///
    /// - Parameters:
    ///     - contents: The report to write.
    ///     - body: What to do with its location.
    ///
    private func withReport(_ contents: String, _ body: (URL) throws -> Void) throws {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: JUnitReader.fileName, directoryHint: .notDirectory)
        try Data(contents.utf8).write(to: url)
        try body(url)
    }

    @Test
    func `A report whose every suite ran nothing says nothing ran.`() throws {
        try withReport(#"""
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.0005"/>
        </testsuites>
        """#) { url in
            #expect(!JUnitReader.ranAnyTests(in: url))
        }
    }

    @Test
    func `An empty suite beside one which ran does not hide it.`() throws {
        // The regression this exists for. A toolchain which runs no XCTest tests still writes an empty element for that system, and the check used to look for `tests="0"` anywhere in the file.
        try withReport(#"""
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.0005"/>
            <testsuite name="TestResults" errors="0" tests="3" failures="0" skipped="0" time="21.8">
                <testcase classname="FileProviderTests.DomainLifecycleTests" name="`Configuring an account produces a File Provider domain.`(_:)" time="7.6"/>
            </testsuite>
        </testsuites>
        """#) { url in
            #expect(JUnitReader.ranAnyTests(in: url))
        }
    }

    @Test
    func `A report which cannot be read counts as having run.`() {
        // Deliberately the forgiving direction: failing a green run because its report is missing would be worse than missing a mistyped filter.
        #expect(JUnitReader.ranAnyTests(in: URL(filePath: "/nowhere/\(UUID().uuidString)/\(JUnitReader.fileName)", directoryHint: .notDirectory)))
    }

    @Test
    func `A report holding no count at all counts as having run.`() throws {
        try withReport("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites></testsuites>") { url in
            #expect(JUnitReader.ranAnyTests(in: url))
        }
    }
}
