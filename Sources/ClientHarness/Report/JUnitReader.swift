// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Reads the failures out of the xUnit report a run always writes.
///
/// This is the poorer of the two accounts and exists only so that a run which has no event stream still produces something. It records one entry per test function rather than per case, so a test which failed against one server and passed against another appears as a single entry with no way to tell which — and it timestamps nothing, so a failure read from here cannot be placed in the clean room it happened in.
///
/// Anything drawn from here is therefore marked as lacking attribution rather than quietly presented as complete.
///
public enum JUnitReader {
    ///
    /// How the testing library introduces an error which escaped a test, as opposed to an expectation which failed.
    ///
    /// The xUnit report keeps no field for the distinction, so this prefix is all that survives of it — and the distinction decides whether a document is a bug report or a record of a measurement that never happened.
    ///
    static let thrownErrorPrefix = "Caught error: "

    ///
    /// The name of the file a run writes its results to.
    ///
    /// Not the name the runner asks for. The option takes `results.xml`, and the testing library writes this instead.
    ///
    public static let fileName = "results-swift-testing.xml"

    ///
    /// Whether the report says that any test ran at all.
    ///
    /// A mistyped filter matches nothing, and the test process then exits successfully having done nothing, mentioning it only in a warning. Without this a typo reads as a clean run of the whole suite, which is the most expensive way to be told nothing.
    ///
    /// The report holds one `testsuite` element per testing system, and a toolchain which ran no XCTest tests still writes an empty one for it. Asking whether the text anywhere contains `tests="0"` therefore finds that empty element and calls a green run empty — which is what it did, to three passing runs in a row, once the toolchain started emitting it.
    ///
    /// - Parameters:
    ///     - url: The file to read.
    ///
    /// - Returns: `false` only when the report is readable and every suite in it ran nothing. An absent or unreadable report counts as having run, because failing a green run over a reporting problem would be worse than missing this.
    ///
    public static func ranAnyTests(in url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return true
        }

        let counts = contents.matches(of: /tests="([0-9]+)"/).compactMap { Int($0.1) }

        guard !counts.isEmpty else {
            return true
        }

        return counts.contains { $0 > 0 }
    }

    ///
    /// Read the failures a run recorded.
    ///
    /// - Parameters:
    ///     - url: The file to read.
    ///
    /// - Returns: The failures, or an empty array if there are none or the file cannot be read.
    ///
    public static func failures(in url: URL) -> [ReportedFailure] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var failures = [ReportedFailure]()
        var testName = ""
        var className = ""

        // The shape is small and fixed — testsuite, testcase, failure, with a handful of attributes — so it is read by scanning rather than by standing up a parser delegate for it.
        for element in contents.components(separatedBy: "<").dropFirst() {
            if element.hasPrefix("testcase ") {
                className = attribute("classname", in: element) ?? className
                testName = attribute("name", in: element) ?? ""
            }

            guard element.hasPrefix("failure "), let message = attribute("message", in: element) else {
                continue
            }

            let decoded = decode(message)

            failures.append(ReportedFailure(
                testIdentifier: className.isEmpty ? testName : "\(className)/\(testName)",
                testDisplayName: testName.replacingOccurrences(of: "`", with: ""),
                message: decoded,
                // This file carries no structured record of whether the test threw or contradicted an expectation, and letting the field take its default would answer "contradicted an expectation" — which is the answer that turns an abandoned measurement into a bug report somebody files. The prefix is the only signal the format preserves, and reading it wrongly costs a caveat on a document rather than a false claim in one.
                thrownError: decoded.hasPrefix(thrownErrorPrefix) ? String(decoded.dropFirst(thrownErrorPrefix.count)) : nil
            ))
        }

        return failures
    }

    ///
    /// Read one attribute of an element.
    ///
    /// - Parameters:
    ///     - name: The attribute.
    ///     - element: The element, without its opening angle bracket.
    ///
    /// - Returns: The value, if it has one.
    ///
    private static func attribute(_ name: String, in element: String) -> String? {
        guard let range = element.range(of: "\(name)=\"") else {
            return nil
        }

        let rest = element[range.upperBound...]

        guard let end = rest.firstIndex(of: "\"") else {
            return nil
        }

        return String(rest[..<end])
    }

    ///
    /// Turn the entities an attribute is written with back into what they stand for.
    ///
    /// - Parameters:
    ///     - text: The attribute value.
    ///
    /// - Returns: The text.
    ///
    private static func decode(_ text: String) -> String {
        var decoded = text

        for (entity, character) in [("&#10;", "\n"), ("&quot;", "\""), ("&#8594;", "→"), ("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'"), ("&amp;", "&")] {
            decoded = decoded.replacingOccurrences(of: entity, with: character)
        }

        return decoded
    }
}
