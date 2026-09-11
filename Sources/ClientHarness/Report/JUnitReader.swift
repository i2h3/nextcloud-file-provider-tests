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
    /// The name of the file a run writes its results to.
    ///
    /// Not the name the runner asks for. The option takes `results.xml`, and the testing library writes this instead.
    ///
    public static let fileName = "results-swift-testing.xml"

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

            failures.append(ReportedFailure(
                testIdentifier: className.isEmpty ? testName : "\(className)/\(testName)",
                testDisplayName: testName.replacingOccurrences(of: "`", with: ""),
                message: decode(message)
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
