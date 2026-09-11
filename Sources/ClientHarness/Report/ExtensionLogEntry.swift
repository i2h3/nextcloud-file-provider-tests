// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One line of the File Provider extension's own log.
///
/// The extension writes a JSON object per line with five fields, one of which — `details` — is free-form and carries whatever the line was about: the item, its name, the account, the domain.
///
/// The timestamp has no time zone. It is local to the machine which wrote it, which is why reading a log later needs the run's recorded zone and cannot be done from the file alone.
///
public struct ExtensionLogEntry: Sendable {
    ///
    /// The type which wrote the line.
    ///
    public let category: String

    ///
    /// When it was written, once a zone has been supplied.
    ///
    public let date: Date?

    ///
    /// How important the extension considered it.
    ///
    public let level: String

    ///
    /// What it said.
    ///
    public let message: String

    ///
    /// Whatever the line was about.
    ///
    public let details: [String: String]

    ///
    /// The line as it was written, for quoting.
    ///
    public let rendered: String

    ///
    /// A value the extension writes when it was asked to log an error and there was none.
    ///
    /// Worth knowing about because a rule which treats the presence of an error as a sign of trouble would select exactly the lines which say nothing went wrong.
    ///
    public static let absentErrorSentinel = "Unsupported log detail type: nil"

    ///
    /// Whether the line reports something which actually went wrong.
    ///
    public var reportsError: Bool {
        guard let error = details["error"] else {
            return false
        }

        return error != Self.absentErrorSentinel
    }

    ///
    /// Read one line.
    ///
    /// - Parameters:
    ///     - line: The line as the extension wrote it.
    ///     - timeZone: The zone the machine was in, since the line does not say.
    ///
    /// - Returns: The entry, or `nil` if the line is not one.
    ///
    public static func parse(_ line: some StringProtocol, timeZone: TimeZone) -> ExtensionLogEntry? {
        guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["message"] as? String else {
            return nil
        }

        var details = [String: String]()

        for (key, value) in object["details"] as? [String: Any] ?? [:] {
            details[key] = String(describing: value)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        return ExtensionLogEntry(
            category: object["category"] as? String ?? "",
            date: (object["date"] as? String).flatMap { formatter.date(from: $0) },
            level: object["level"] as? String ?? "",
            message: message,
            details: details,
            rendered: String(line)
        )
    }

    ///
    /// Read a whole log.
    ///
    /// - Parameters:
    ///     - url: The file to read.
    ///     - timeZone: The zone the machine was in.
    ///
    /// - Returns: The entries, skipping anything unreadable.
    ///
    public static func read(from url: URL, timeZone: TimeZone) -> [ExtensionLogEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return contents.split(separator: "\n").compactMap { parse($0, timeZone: timeZone) }
    }

    ///
    /// Describe a line.
    ///
    /// - Parameters:
    ///     - category: The type which wrote it.
    ///     - date: When it was written.
    ///     - level: How important the extension considered it.
    ///     - message: What it said.
    ///     - details: Whatever it was about.
    ///     - rendered: The line as written.
    ///
    public init(category: String, date: Date?, level: String, message: String, details: [String: String], rendered: String) {
        self.category = category
        self.date = date
        self.details = details
        self.level = level
        self.message = message
        self.rendered = rendered
    }
}
