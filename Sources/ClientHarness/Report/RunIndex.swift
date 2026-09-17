// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Renders one page which says what a run did.
///
/// A run leaves seven kinds of artifact behind and no way in. The terminal prints one line per test case and scrolls; the xUnit report cannot say which cell failed; the measurements are one file per measurement; the rooms are named after Nextcloud users. Everything needed to understand a run is present and nothing assembles it, so reading a run has meant opening manifests and inferring from ordering.
///
/// This is the way in. It is written beside the artifacts it describes, opens without a server, and embeds its own styling, because these directories get zipped and sent to people who will not run a build to read them.
///
/// What it is careful about, in order of how easily each would mislead:
///
/// **A declined clause is not a passing one.** A cell whose oracle could not be judged is shown as such rather than as green, because the whole value of the suite is that it says what it did not measure.
///
/// **A failure belongs to a room.** The join is the room's time window — everything is serialized, so the room whose window contains a failure is that failure's room — and the room now records its cell, so the link from a red row to the client and extension logs is exact rather than inferred.
///
/// **A run is about a machine and a client.** The header carries what `run.json` knows and nobody opens: the operating system, the client build, whether the system policy was waived, and which servers answered with which versions.
///
public enum RunIndex {
    ///
    /// The name of the page.
    ///
    public static let fileName = "index.html"

    ///
    /// Assemble the page for a run.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: A self-contained HTML document.
    ///
    public static func render(_ evidence: RunEvidence) -> String {
        let rooms = evidence.rooms.sorted { ($0.cell ?? $0.testName) < ($1.cell ?? $1.testName) }
        let samples = latencies(in: evidence.directory)
        let failuresByRoom = attribute(evidence.failures, to: rooms)
        let quadrants = group(rooms)

        var html = header(evidence)

        html += summary(rooms: rooms, failures: evidence.failures, quadrants: quadrants, samples: samples)

        for (quadrant, members) in quadrants.sorted(by: { $0.key < $1.key }) {
            html += section(quadrant, rooms: members, failures: failuresByRoom, samples: samples)
        }

        html += unattributed(evidence.failures, attributed: failuresByRoom)
        html += footer(evidence)

        return html
    }

    ///
    /// Write the page into the run's directory.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: Where it was written.
    ///
    /// - Throws: Whatever writing raises.
    ///
    @discardableResult
    public static func write(for evidence: RunEvidence) throws -> URL {
        let url = evidence.directory.appending(path: fileName, directoryHint: .notDirectory)
        try Data(render(evidence).utf8).write(to: url)

        return url
    }

    // MARK: - Assembling

    ///
    /// Which quadrant a room belongs to, taken from its cell and falling back to its test name.
    ///
    /// - Parameters:
    ///     - rooms: The rooms.
    ///
    /// - Returns: The rooms grouped.
    ///
    static func group(_ rooms: [RoomManifest]) -> [String: [RoomManifest]] {
        Dictionary(grouping: rooms) { room in
            // A cell's description opens with its origin and its operation, which is exactly its quadrant.
            guard let cell = room.cell else {
                // A room from before the cell was recorded, or one belonging to a hand-written suite which has no cell at all. Its test name opens with the suite, which is the closest thing to a quadrant either of them has.
                return room.testName.split(separator: ".").first.map(String.init) ?? room.testName
            }

            return cell.split(separator: " ").prefix(2).joined(separator: " ")
        }
    }

    ///
    /// Attach each failure to the room whose window contains it.
    ///
    /// Everything is serialized and one room is occupied at a time, so a failure's instant identifies its room without ambiguity. A failure with no timestamp, or one which happened while no room was open, is left out and listed separately rather than attached to a plausible neighbour.
    ///
    /// - Parameters:
    ///     - failures: What went wrong.
    ///     - rooms: The rooms of the run.
    ///
    /// - Returns: The failures of each room, by user.
    ///
    static func attribute(_ failures: [ReportedFailure], to rooms: [RoomManifest]) -> [String: [ReportedFailure]] {
        var attributed = [String: [ReportedFailure]]()

        for failure in failures {
            guard let instant = failure.occurredAt else {
                continue
            }

            guard let room = rooms.first(where: { $0.startedAt <= instant && ($0.endedAt ?? Date.distantFuture) >= instant }) else {
                continue
            }

            attributed[room.user, default: []].append(failure)
        }

        return attributed
    }

    ///
    /// Read the measurements a run recorded.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///
    /// - Returns: The samples, by the cell they were taken for.
    ///
    static func latencies(in directory: URL) -> [String: [LatencySample]] {
        let attachments = directory.appending(path: "attachments", directoryHint: .isDirectory)
        let decoder = JSONDecoder()

        guard let entries = try? FileManager.default.contentsOfDirectory(at: attachments, includingPropertiesForKeys: nil) else {
            return [:]
        }

        var samples = [String: [LatencySample]]()

        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry), let sample = try? decoder.decode(LatencySample.self, from: data) else {
                continue
            }

            samples[sample.test, default: []].append(sample)
        }

        return samples
    }

    // MARK: - Rendering

    ///
    /// The document's opening, its styling and what the run was.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The markup.
    ///
    static func header(_ evidence: RunEvidence) -> String {
        let manifest = evidence.manifest
        let identifier = manifest?.runIdentifier ?? evidence.directory.lastPathComponent

        var facts = [(String, String)]()

        if let machine = manifest?.machine {
            facts.append(("macOS", machine["operatingSystemVersionString"] ?? machine["operatingSystem"] ?? "unknown"))
            facts.append(("Architecture", machine["architecture"] ?? "unknown"))
        }

        for check in manifest?.preflight.checks ?? [] where check.subject == "Desktop client" || check.subject == "System policy" {
            facts.append((check.subject, check.detail))
        }

        for server in manifest?.servers ?? [] {
            facts.append(("Server \(server.tag)\(server.isPushEnabled ? " with push" : "")", "\(server.versionString ?? "unknown") at \(server.serverAddress)"))
        }

        let rows = facts.map { "<tr><th>\(escape($0.0))</th><td>\(escape($0.1))</td></tr>" }.joined()

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Run \(escape(identifier))</title><style>
        :root { color-scheme: light dark; --ink: #1c1c1e; --dim: #6c6c70; --line: #d8d8dd; --bg: #fdfdfd; --panel: #fff;
                --pass: #1d7a3f; --fail: #c0392b; --skip: #8a6d1f; --accent: #2a5db0; }
        @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f7; --dim: #98989f; --line: #34343a; --bg: #161618;
                --panel: #1f1f22; --pass: #4cc26a; --fail: #ff6b5a; --skip: #d8b34a; --accent: #7fa8f0; } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 2rem 1.5rem 4rem; background: var(--bg); color: var(--ink);
               font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
        main { max-width: 68rem; margin: 0 auto; }
        h1 { font-size: 1.6rem; margin: 0 0 .25rem; letter-spacing: -.01em; }
        h2 { font-size: 1.05rem; margin: 2.5rem 0 .75rem; letter-spacing: -.005em; }
        .sub { color: var(--dim); margin: 0 0 2rem; }
        table { border-collapse: collapse; width: 100%; font-size: 13.5px; }
        th, td { text-align: left; padding: .45rem .6rem; border-bottom: 1px solid var(--line); vertical-align: top; }
        thead th { color: var(--dim); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
        .facts { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
        .facts th { width: 12rem; color: var(--dim); font-weight: 500; }
        .facts tr:last-child th, .facts tr:last-child td { border-bottom: 0; }
        .legend { margin-top: .5rem; }
        .legend th { width: 9rem; font-weight: 600; vertical-align: top; }
        .legend td { color: var(--dim); font-size: 13px; }
        .legend em { font-style: normal; color: var(--ink); }
        .tally { display: flex; gap: .5rem; flex-wrap: wrap; margin: 0 0 1rem; padding: 0; list-style: none; }
        .tally li { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: .5rem .9rem; }
        .tally b { display: block; font-size: 1.5rem; font-weight: 600; line-height: 1.1; }
        .tally span { color: var(--dim); font-size: 12px; }
        .what { display: block; }
        .exact { display: block; color: var(--dim); font-size: 11.5px; letter-spacing: .01em; margin-top: .15rem; }
        .path { color: var(--dim); font-size: 12px; margin: -1.5rem 0 2rem; }
        .pill { display: inline-block; vertical-align: middle; margin-left: .4rem; padding: .1rem .5rem; border-radius: 999px;
                background: var(--panel); border: 1px solid var(--line); color: var(--dim);
                font-size: 11.5px; font-weight: 500; letter-spacing: .01em; }
        .pill.bad { color: var(--fail); border-color: color-mix(in srgb, var(--fail) 35%, var(--line)); }
        .ok { color: var(--pass); font-weight: 600; }
        .bad { color: var(--fail); font-weight: 600; }
        .meh { color: var(--skip); font-weight: 600; }
        .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .why { color: var(--dim); font-size: 12.5px; margin: .2rem 0 0; }
        tr.failed td { background: color-mix(in srgb, var(--fail) 8%, transparent); }
        @media (max-width: 600px) { body { padding: 1rem .75rem 3rem; } .facts th { width: auto; } }
        </style></head><body><main>
        <h1>Nextcloud File Provider Tests</h1>
        <p class="sub">\(escape(occasion(evidence)))</p>
        <p class="path">\(escape(evidence.directory.path(percentEncoded: false)))</p>
        <table class="facts">\(rows)</table>
        """
    }

    ///
    /// When the run happened, written the way somebody would say it.
    ///
    /// In the run's own time zone rather than the reader's: an artifacts directory is read on other machines and often in other places, and a run's timings only mean anything against the clock it was recorded on. `run.json` carries that zone for the same reason.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The sentence.
    ///
    static func occasion(_ evidence: RunEvidence) -> String {
        guard let started = evidence.manifest?.startedAt else {
            return "Run \(evidence.directory.lastPathComponent)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = evidence.timeZone
        formatter.dateFormat = "HH:mm:ss 'on' d MMMM yyyy"

        guard let finished = evidence.manifest?.finishedAt ?? evidence.rooms.compactMap(\.endedAt).max() else {
            return "Run at \(formatter.string(from: started))"
        }

        return "Run at \(formatter.string(from: started)) for \(spoken(finished.timeIntervalSince(started)))"
    }

    ///
    /// Say a length of time the way somebody would say it aloud.
    ///
    /// Zero components are left out rather than written as zero: "41 minutes and 29 seconds" is what a person says, and "0 hours, 41 minutes and 29 seconds" is what a machine says.
    ///
    /// - Parameters:
    ///     - seconds: How long.
    ///
    /// - Returns: The phrase.
    ///
    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        let parts = [(whole / 3600, "hour"), (whole % 3600 / 60, "minute"), (whole % 60, "second")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }

        guard let last = parts.last else {
            return "less than a second"
        }

        guard parts.count > 1 else {
            return last
        }

        return "\(parts.dropLast().joined(separator: ", ")) and \(last)"
    }

    ///
    /// Say a length of time compactly, for a badge.
    ///
    /// - Parameters:
    ///     - seconds: How long.
    ///
    /// - Returns: The text.
    ///
    static func compact(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())

        guard whole >= 60 else {
            return "\(whole) s"
        }

        guard whole >= 3600 else {
            return "\(whole / 60) min \(whole % 60) s"
        }

        return "\(whole / 3600) h \(whole % 3600 / 60) min"
    }

    ///
    /// The counts, before any detail.
    ///
    /// - Parameters:
    ///     - rooms: The rooms of the run.
    ///     - failures: What went wrong.
    ///     - quadrants: The rooms grouped.
    ///
    /// - Returns: The markup.
    ///
    static func summary(rooms: [RoomManifest], failures: [ReportedFailure], quadrants: [String: [RoomManifest]], samples: [String: [LatencySample]]) -> String {
        let failed = Set(failures.compactMap(\.caseDisplayName)).count
        let spent = rooms.compactMap { room in room.endedAt.map { $0.timeIntervalSince(room.startedAt) } }.reduce(0, +)

        let measured = samples.values.flatMap { $0 }.reduce(0.0) { total, sample in
            total + Double(sample.duration.components.seconds) + Double(sample.duration.components.attoseconds) / 1e18
        }

        // The ratio is the honest thing to show beside the wall clock. Almost all of a run is spent building rooms — a fresh user, a fresh account, a fresh domain, torn down afterwards — and almost none of it is the behaviour under test. Somebody deciding whether to run a quadrant again is deciding about the first number; somebody reading what the client did wants the second.
        let context = spent > 0
            ? "Of \(compact(spent)) across every room, \(compact(measured)) was the client actually carrying a change. The rest is the price of giving each cell a room of its own."
            : ""

        return """
        <h2>At a glance</h2>
        <ul class="tally">
        <li><b>\(rooms.count)</b><span>cells run</span></li>
        <li><b class="\(failures.isEmpty ? "ok" : "bad")">\(failures.count)</b><span>failures</span></li>
        <li><b>\(failed)</b><span>cells affected</span></li>
        <li><b>\(quadrants.count)</b><span>quadrants</span></li>
        </ul>
        <p class="why">\(escape(context))</p>
        <table class="facts legend">
        <tr><th><span class="ok">passed</span></th><td>Everything this cell asserts held, and it recorded how long the change took to propagate. It does <em>not</em> mean every clause of the model was judged: a clause this harness cannot observe is declined rather than asserted, and the run prints the reason.</td></tr>
        <tr><th><span class="bad">failed</span></th><td>An assertion did not hold, or the cell raised before reaching one. The second is not a finding about the client — a cell whose world could not be built measured nothing. The message is on the row and the client and extension logs are behind the link.</td></tr>
        <tr><th><span class="meh">no measurement</span></th><td>The cell ran and nothing went wrong, but no timing was recorded. Either its suite measures nothing, or the cell declined to measure: a concurrent write whose two sides did not overlap has no conflict to resolve and says so rather than passing quietly.</td></tr>
        </table>
        """
    }

    ///
    /// One quadrant's cells.
    ///
    /// - Parameters:
    ///     - quadrant: Its name.
    ///     - rooms: Its rooms.
    ///     - failures: The failures of each room, by user.
    ///     - samples: The measurements, by cell.
    ///
    /// - Returns: The markup.
    ///
    static func section(_ quadrant: String, rooms: [RoomManifest], failures: [String: [ReportedFailure]], samples: [String: [LatencySample]]) -> String {
        var rows = ""

        for room in rooms {
            let mine = failures[room.user] ?? []
            let cell = room.cell ?? room.testName
            let taken = samples[cell]?.compactMap { $0.duration }.max()

            let status = mine.isEmpty
                ? (taken == nil ? "<span class=\"meh\">no measurement</span>" : "<span class=\"ok\">passed</span>")
                : "<span class=\"bad\">failed</span>"

            let detail = mine.map { "<p class=\"why\">\(escape($0.message))</p>" }.joined()
            let elapsed = room.endedAt.map { $0.timeIntervalSince(room.startedAt) }

            rows += """
            <tr class="\(mine.isEmpty ? "" : "failed")">
            <td><span class="what">\(escape(CellPhrase.sentence(for: cell)))</span><span class="exact">\(escape(cell))</span>\(detail)</td>
            <td>\(status)</td>
            <td class="num">\(taken.map { format($0) } ?? "—")</td>
            <td class="num">\(elapsed.map { String(format: "%.0f s", $0) } ?? "—")</td>
            <td><a href="clean-rooms/\(escape(room.user))/">logs</a></td>
            </tr>
            """
        }

        let broken = rooms.filter { !(failures[$0.user] ?? []).isEmpty }.count

        // Wall-clock across the quadrant's rooms, which is what a reader is deciding about when they wonder whether to run it again. Building a room dominates it — a cell's own operation is usually under a second — so this is mostly the price of isolation, and saying so is the point.
        let spent = rooms.compactMap { room in room.endedAt.map { $0.timeIntervalSince(room.startedAt) } }.reduce(0, +)

        return """
        <h2>\(escape(CellPhrase.heading(for: quadrant))) <span class="pill">\(rooms.count) cells</span> <span class="pill">\(compact(spent))</span>\(broken > 0 ? " <span class=\"pill bad\">\(broken) failed</span>" : "")</h2>
        <table><thead><tr><th>Cell</th><th>Outcome</th><th class="num">Propagated in</th><th class="num">Room took</th><th>Evidence</th></tr></thead>
        <tbody>\(rows)</tbody></table>
        """
    }

    ///
    /// Failures which belong to no room.
    ///
    /// Shown rather than dropped: a failure outside every room's window is usually one raised while a room was being built or torn down, which is exactly when the room has the least to say for itself.
    ///
    /// - Parameters:
    ///     - failures: Every failure.
    ///     - attributed: The ones already placed.
    ///
    /// - Returns: The markup.
    ///
    static func unattributed(_ failures: [ReportedFailure], attributed: [String: [ReportedFailure]]) -> String {
        let placed = Set(attributed.values.flatMap { $0 }.map(\.message))
        let rest = failures.filter { !placed.contains($0.message) }

        guard !rest.isEmpty else {
            return ""
        }

        let rows = rest.map { failure in
            "<tr><td><span class=\"what\">\(escape(CellPhrase.sentence(for: failure.caseDisplayName ?? failure.testDisplayName ?? "unknown")))</span></td><td>\(escape(failure.message))</td></tr>"
        }.joined()

        return """
        <h2>Failures outside any room</h2>
        <table><thead><tr><th>Case</th><th>What happened</th></tr></thead><tbody>\(rows)</tbody></table>
        """
    }

    ///
    /// The document's close.
    ///
    /// - Parameters:
    ///     - evidence: What the run left behind.
    ///
    /// - Returns: The markup.
    ///
    static func footer(_ evidence: RunEvidence) -> String {
        """
        <h2>Reading this further</h2>
        <table class="facts">
        <tr><th>Per-case detail</th><td>events.jsonl\(evidence.hasCaseAttribution ? "" : " — absent, so failures above are attributed by time window only")</td></tr>
        <tr><th>Measurements</th><td>metrics.md, attachments/</td></tr>
        <tr><th>Drafted reports</th><td>reports/ — unfiled drafts, never findings on their own</td></tr>
        <tr><th>The run itself</th><td>run.json — machine, client, preflight, servers, flags</td></tr>
        </table>
        </main></body></html>
        """
    }

    ///
    /// Render a duration the way a person reads one.
    ///
    /// - Parameters:
    ///     - duration: The duration.
    ///
    /// - Returns: The text.
    ///
    static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

        return seconds < 10 ? String(format: "%.2f s", seconds) : String(format: "%.1f s", seconds)
    }

    ///
    /// Make text safe to place in markup.
    ///
    /// - Parameters:
    ///     - text: The text.
    ///
    /// - Returns: The escaped text.
    ///
    static func escape(_ text: some StringProtocol) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
