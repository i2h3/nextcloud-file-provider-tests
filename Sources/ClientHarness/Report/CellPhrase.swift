// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Says in English what a cell of the scenario matrix describes.
///
/// A cell's own description is written to be exact and to sort well — `local delete item:dataless kind:folderEmpty at:standard:root trash:with` — which makes it a good identifier and a poor sentence. Somebody reading a run wants to know that this was a deletion, in the client, of a folder nobody had opened; the axis names are how the suite talks to itself.
///
/// So both are shown, and this produces the first of them. The exact description stays beneath it, because it is what a filter matches, what a report quotes, and what makes two similar rows distinguishable.
///
/// Anything it cannot parse comes back unchanged. An unrecognised axis value is a description that is still correct, which is the failure worth having here — a phrase that quietly drops an axis would make two different cells read identically.
///
public enum CellPhrase {
    ///
    /// Turn a cell's description into a sentence.
    ///
    /// - Parameters:
    ///     - cell: The description, as the model writes it.
    ///
    /// - Returns: The sentence.
    ///
    public static func sentence(for cell: String) -> String {
        let tokens = cell.split(separator: " ").map(String.init)

        guard tokens.count > 2, let origin = origins[tokens[0]], let operation = operations[tokens[1]] else {
            return humanize(cell)
        }

        var attributes = [String: String]()

        for token in tokens.dropFirst(2) {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)

            guard parts.count == 2 else {
                continue
            }

            attributes[parts[0]] = parts[1]
        }

        var phrase = "\(origin) \(operation) of "
        phrase += subject(attributes)

        if let where_ = place(attributes) {
            phrase += " \(where_)"
        }

        if let trash = attributes["trash"] {
            phrase += ", with Nextcloud server trash \(trash == "with" ? "enabled" : "disabled")"
        }

        return phrase
    }

    ///
    /// Turn a quadrant's name into a heading.
    ///
    /// - Parameters:
    ///     - quadrant: Either `concurrent contentUpdate` as a cell opens, or `ConcurrentContentUpdate` as a suite is named.
    ///
    /// - Returns: The heading.
    ///
    public static func heading(for quadrant: String) -> String {
        let words = quadrant.split(whereSeparator: { $0 == " " || $0 == "." }).flatMap { splitCamelCase(String($0)) }

        return words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    // MARK: - Vocabulary

    ///
    /// Who acted.
    ///
    static let origins = ["local": "Local", "remote": "Remote", "concurrent": "Concurrent"]

    ///
    /// What they did, as a noun.
    ///
    static let operations = [
        "create": "creation",
        "delete": "deletion",
        "move": "move",
        "metadataUpdate": "rename",
        "contentUpdate": "content change",
    ]

    ///
    /// How much of the item was on disk.
    ///
    /// The framework's own words, deliberately. The page is read beside Apple's documentation and beside the model, and a reader who learns "never-downloaded" here has learned a word which appears in neither.
    static let levels = [
        "dataless": "dataless",
        "materialized": "materialized",
        "evicted": "evicted",
        "materializedDeep": "deeply materialized",
        "unknown": "unknown",
    ]

    ///
    /// What sort of thing it is.
    ///
    static let kinds = [
        "file": "file",
        "folderEmpty": "empty folder",
        "folderWithChildren": "non-empty folder",
        "bundle": "bundle",
    ]

    ///
    /// Where it sits.
    ///
    /// "The domain root" rather than "the top level": it is the framework's own name for the container everything else hangs from, and it cannot be misread as the top of anything else.
    ///
    static let places = ["root": "the domain root", "subdirectory": "a subfolder"]

    // MARK: - Assembling

    ///
    /// The noun phrase for the item itself.
    ///
    /// - Parameters:
    ///     - attributes: The cell's axis values.
    ///
    /// - Returns: The phrase.
    ///
    static func subject(_ attributes: [String: String]) -> String {
        let kind = kinds[attributes["kind"] ?? ""] ?? "item"
        var adjectives = [String]()

        // The realization belongs to the item only when the cell says `item:`. For a create it describes the container the item goes into, and for a move the two containers it travels between, so attaching it to the item here would say the opposite of what the cell means.
        if let level = attributes["item"], let described = levels[level] {
            adjectives.append(described)
        }

        if let size = attributes["size"], size != "small" {
            adjectives.append(size == "empty" ? "empty" : size)
        } else if attributes["size"] == "small", attributes["kind"] == "file" {
            adjectives.append("small")
        }

        return "\(article(adjectives.first ?? kind)) \(adjectives.joined(separator: " ")) \(kind)".replacingOccurrences(of: "  ", with: " ")
    }

    ///
    /// The phrase saying where it happened, including the state of the containers when the cell pins those.
    ///
    /// - Parameters:
    ///     - attributes: The cell's axis values.
    ///
    /// - Returns: The phrase, or `nil` when the cell says nothing about place.
    ///
    static func place(_ attributes: [String: String]) -> String? {
        if let pair = attributes["parents"], let from = attributes["from"], let to = attributes["to"] {
            let levels = pair.components(separatedBy: "->")

            return "from \(container(from, level: levels.first)) into \(container(to, level: levels.last))"
        }

        guard let at = attributes["at"] else {
            return nil
        }

        // The container's own state, where the cell pins it, belongs to the phrase naming the container rather than trailing after it as a second clause about an unnamed folder.
        return "in \(container(at, level: attributes["parent"]))"
    }

    ///
    /// Name a container, and say what the client knew of it where the cell says so.
    ///
    /// - Parameters:
    ///     - placement: The location, as the cell spells it.
    ///     - level: The realization the cell pins for that container, if it pins one.
    ///
    /// - Returns: The phrase.
    ///
    static func container(_ placement: String, level: String?) -> String {
        let place = places[placement.components(separatedBy: ":").last ?? ""] ?? "an unknown container"

        // The domain root is enumerated the moment the domain mounts, so its state is never in question and saying anything about it would be noise.
        guard place != places["root"], let level, let described = levels[level] else {
            return place
        }

        return described == "dataless" ? "\(place) the client had never enumerated" : "\(place) the client had enumerated"
    }

    ///
    /// The indefinite article for a word.
    ///
    /// - Parameters:
    ///     - word: The word.
    ///
    /// - Returns: `"a"` or `"an"`.
    ///
    static func article(_ word: String) -> String {
        "aeiou".contains(word.lowercased().prefix(1)) ? "an" : "a"
    }

    ///
    /// Make a technical identifier readable when it cannot be parsed as a cell.
    ///
    /// - Parameters:
    ///     - text: The identifier.
    ///
    /// - Returns: The readable form.
    ///
    static func humanize(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0 == "." || $0 == " " }).flatMap { splitCamelCase(String($0)) }

        guard let first = words.first else {
            return text
        }

        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }

    ///
    /// Break a camel-cased word into its parts.
    ///
    /// - Parameters:
    ///     - word: The word.
    ///
    /// - Returns: Its parts.
    ///
    static func splitCamelCase(_ word: String) -> [String] {
        var parts = [String]()
        var current = ""

        for character in word {
            if character.isUppercase, !current.isEmpty {
                parts.append(current)
                current = ""
            }

            current.append(character)
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }
}
