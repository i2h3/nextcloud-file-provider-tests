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
        let seen = observations(in: evidence.directory)
        let failuresByRoom = attribute(evidence)
        let quadrants = group(rooms)

        let reached = verdicts(rooms: rooms, failures: failuresByRoom, samples: samples)
        let ordered = quadrants.sorted { $0.key < $1.key }

        // No cell description carries a server, so a run which deployed more than one writes every label on the page twice — generated cells included. Asked of the rooms rather than of the manifest, because a run whose manifest is missing still has to be readable.
        let namesServer = Set(rooms.map(\.server.tag)).count > 1

        var html = header(evidence)

        html += summary(rooms: rooms, failures: evidence.failures, quadrants: quadrants, samples: samples)
        html += heatMap(ordered, verdicts: reached, namesServer: namesServer)

        for (quadrant, members) in ordered {
            html += section(quadrant, rooms: members, failures: failuresByRoom, samples: samples, observations: seen.byRoom, verdicts: reached, namesServer: namesServer)
        }

        html += notJudged(seen.run)
        html += unattributed(evidence.failures, attributed: failuresByRoom)
        html += footer(evidence)
        html += script(total: rooms.count, quadrants: ordered.count)

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
    /// Attach each failure to the room it happened in.
    ///
    /// The rule itself is ``RunEvidence/room(of:)`` and deliberately not repeated here. It used to be: this file carried its own window check plus a correction for errors recorded after their room was torn down, and the report generator carried the window check without the correction — so the page named the right room while the documents drafted from the same run named none at all. One rule, one place.
    ///
    /// - Parameters:
    ///     - evidence: The run.
    ///
    /// - Returns: The failures of each room, by user.
    ///
    static func attribute(_ evidence: RunEvidence) -> [String: [ReportedFailure]] {
        var attributed = [String: [ReportedFailure]]()

        for failure in evidence.failures {
            guard let room = evidence.room(of: failure) else {
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
        .saw { color: var(--dim); font-size: 12.5px; margin: .2rem 0 0; padding-left: .75rem; border-left: 2px solid var(--line); }
        .declines { color: var(--dim); font-size: 13.5px; margin: .4rem 0 0; padding-left: 1.1rem; }
        .declines li { margin: .3rem 0; }
        tr.failed td { background: color-mix(in srgb, var(--fail) 8%, transparent); }
        tr:target td { background: color-mix(in srgb, var(--accent) 14%, transparent); }
        .controls { display: flex; align-items: center; gap: .5rem; flex-wrap: wrap; margin: .6rem 0 1rem; }
        .controls label { color: var(--dim); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; font-weight: 600; }
        .controls select { font: inherit; font-size: 13px; padding: .25rem .5rem; border-radius: 8px;
                           border: 1px solid var(--line); background: var(--panel); color: var(--ink); }
        .controls .why { margin: 0; }
        .map { display: flex; flex-wrap: wrap; gap: .85rem 1.2rem; margin: 0 0 1.5rem; }
        .group { width: calc(12 * 12px + 11 * 2px); }
        .group h3 { margin: 0 0 .3rem; font-size: 11px; font-weight: 600; color: var(--dim);
                    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .squares { display: grid; grid-template-columns: repeat(12, 12px); gap: 2px; }
        .sq { display: block; width: 12px; height: 12px; border-radius: 2px; border: 1px solid var(--dim); position: relative; }
        .sq span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
        .sq[data-outcome="passed"] { background: var(--pass); }
        .sq[data-outcome="failed"] { background: var(--fail); }
        .sq[data-outcome="known-limitation"] { background: repeating-linear-gradient(45deg, var(--skip), var(--skip) 3px, var(--panel) 3px, var(--panel) 6px); }
        .sq[data-outcome="not-measured"] { background: var(--panel); border-style: dashed; }
        .sq:hover, .sq:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; z-index: 1; }
        section.quadrant[hidden] { display: none; }
        \(filterRules())
        .sq em { display: none; font-style: normal; font-size: 8px; line-height: 10px; text-align: center; color: var(--bg); }
        .sq[data-outcome="failed"] em, .sq[data-outcome="known-limitation"] em { display: block; }
        section.quadrant.empty table { display: none; }
        section.quadrant.empty h2 { opacity: .45; }
        @media (forced-colors: active) { .sq { forced-color-adjust: none; border-color: CanvasText; } .sq em { display: block; color: CanvasText; } }
        @media print {
            .controls { display: none; }
            .sq { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
            .sq em { display: block; }
        }
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
        let unexpected = failures.filter { !$0.isKnown }
        let failed = Set(unexpected.compactMap(\.caseDisplayName)).count
        let spent = rooms.compactMap { room in room.endedAt.map { $0.timeIntervalSince(room.startedAt) } }.reduce(0, +)

        let measured = samples.values.flatMap(\.self).reduce(0.0) { total, sample in
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
        <li><b class="\(unexpected.isEmpty ? "ok" : "bad")">\(unexpected.count)</b><span>failures</span></li>
        <li><b class="meh">\(failures.count - unexpected.count)</b><span>known limitations</span></li>
        <li><b>\(failed)</b><span>cells affected</span></li>
        <li><b>\(quadrants.count)</b><span>quadrants</span></li>
        </ul>
        <p class="why">\(escape(context))</p>
        <table class="facts legend">
        <tr><th><span class="ok">passed</span></th><td>Everything this cell asserts held, and it recorded how long the change took to propagate. It does <em>not</em> mean every clause of the model was judged: a clause this harness cannot observe is declined rather than asserted, and the run prints the reason.</td></tr>
        <tr><th><span class="bad">failed</span></th><td>An assertion did not hold, or the cell raised before reaching one. The second is not a finding about the client — a cell whose world could not be built measured nothing. The message is on the row and the client and extension logs are behind the link.</td></tr>
        <tr><th><span class="meh">known limitation</span></th><td>The cell failed and was expected to. Its subject declines the feature deliberately and the reason is on the row. It runs anyway, so that the day the client starts doing what the cell asks, the expectation fails instead and somebody is told — coverage nobody can forget to switch back on.</td></tr>
        <tr><th><span class="meh">no measurement</span></th><td>The cell ran and nothing went wrong, but no timing was recorded. Either its suite measures nothing, or the cell declined to measure: a concurrent write whose two sides did not overlap has no conflict to resolve and says so rather than passing quietly.</td></tr>
        <tr><th>observed</th><td>An indented note under a cell, on passing rows as much as failing ones. It is something the cell saw and is <em>not</em> entitled to assert, because the system is allowed either answer — whether a volume holds two names differing only by case, or renames the arriving one. Demanding one of them would fail on a machine formatted the other way; accepting both silently would leave the axis measuring nothing. So the run records which happened here.</td></tr>
        </table>
        """
    }

    ///
    /// Read what the cells of a run saw but did not judge.
    ///
    /// - Parameters:
    ///     - directory: The run's directory.
    ///
    /// - Returns: The observations of each clean room, and the ones belonging to the run rather than to any one cell.
    ///
    static func observations(in directory: URL) -> (byRoom: [String: [Observation]], run: [Observation]) {
        let attachments = directory.appending(path: "attachments", directoryHint: .isDirectory)
        let decoder = JSONDecoder()

        guard let entries = try? FileManager.default.contentsOfDirectory(at: attachments, includingPropertiesForKeys: nil) else {
            return ([:], [])
        }

        var byRoom = [String: [Observation]]()
        var run = [Observation]()

        for entry in entries where entry.lastPathComponent.hasSuffix(Observation.attachmentSuffix) {
            guard let data = try? Data(contentsOf: entry), let observation = try? decoder.decode(Observation.self, from: data) else {
                continue
            }

            guard let user = observation.user else {
                run.append(observation)

                continue
            }

            byRoom[user, default: []].append(observation)
        }

        return (byRoom.mapValues { $0.sorted { $0.recordedAt < $1.recordedAt } }, run.sorted { $0.text < $1.text })
    }

    ///
    /// What the run said it could not judge.
    ///
    /// Given its own block rather than a row, because it is a property of the suite rather than of any cell: the same clause is declined for the same reason everywhere it appears. Shown at all because a clause quietly missing from an evaluation is indistinguishable from one which passed, and this page's whole job is to stop a reader concluding more from a green row than the row supports.
    ///
    /// - Parameters:
    ///     - observations: The run's own observations.
    ///
    /// - Returns: The markup, or nothing if the run declined nothing.
    ///
    static func notJudged(_ observations: [Observation]) -> String {
        let declines = observations.filter(\.isDecline)

        guard !declines.isEmpty else {
            return ""
        }

        return """
        <h2>Not judged <span class="pill">\(declines.count)</span></h2>
        <p class="why">Clauses of the model which this run could not measure. A cell above may have passed without any of these being checked, which is why they are listed rather than left out.</p>
        <ul class="declines">\(declines.map { "<li>\(escape($0.text))</li>" }.joined())</ul>
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
    ///     - observations: What the cells saw and did not judge, by clean room.
    ///
    /// - Returns: The markup.
    ///
    static func section(_ quadrant: String, rooms: [RoomManifest], failures: [String: [ReportedFailure]], samples: [String: [LatencySample]], observations: [String: [Observation]], verdicts: [String: CellOutcome], namesServer: Bool) -> String {
        var rows = ""

        for room in rooms {
            let mine = failures[room.user] ?? []
            let cell = room.cell ?? room.testName
            let taken = samples[cell]?.compactMap(\.duration).max()

            // Read rather than decided here, so that the row and its square in the heat map cannot disagree. ``CellOutcome`` carries the rule, including the part worth stating twice: a known issue is not a failure, because a red row would train a reader to ignore exactly the rows which will one day mean something.
            let outcome = verdicts[room.user] ?? .notMeasured
            let status = "<span class=\"\(outcome.emphasis)\">\(outcome.label)</span>"

            var detail = mine.map { "<p class=\"why\">\(escape($0.message))</p>" }.joined()

            // Shown on a passing row as readily as on a failing one, which is the point of it. An observation is what the cell was not entitled to assert, so the row says "passed" either way and this is the only place the run says which of the permitted things happened.
            detail += (observations[room.user] ?? []).map { "<p class=\"saw\">\(escape($0.text))</p>" }.joined()
            let elapsed = room.endedAt.map { $0.timeIntervalSince(room.startedAt) }

            rows += """
            <tr id="\(escape(anchor(of: room)))" data-outcome="\(outcome.rawValue)" class="cell\(outcome == .failed ? " failed" : "")">
            <td><span class="what">\(escape(headline(of: room)))</span><span class="exact">\(escape(identity(of: room, namesServer: namesServer)))</span>\(detail)</td>
            <td>\(status)</td>
            <td class="num">\(taken.map { format($0) } ?? "—")</td>
            <td class="num">\(elapsed.map { String(format: "%.0f s", $0) } ?? "—")</td>
            <td><a href="clean-rooms/\(escape(room.user))/">logs</a></td>
            </tr>
            """
        }

        let broken = rooms.filter { verdicts[$0.user] == .failed }.count

        // Wall-clock across the quadrant's rooms, which is what a reader is deciding about when they wonder whether to run it again. Building a room dominates it — a cell's own operation is usually under a second — so this is mostly the price of isolation, and saying so is the point.
        let spent = rooms.compactMap { room in room.endedAt.map { $0.timeIntervalSince(room.startedAt) } }.reduce(0, +)

        return """
        <section class="quadrant" data-quadrant="\(escape(quadrant))">
        <h2>\(escape(CellPhrase.heading(for: quadrant))) <span class="pill shown" data-total="\(rooms.count)">\(rooms.count) cells</span> <span class="pill">\(compact(spent))</span>\(broken > 0 ? " <span class=\"pill bad\">\(broken) failed</span>" : "")</h2>
        <table><thead><tr><th>Cell</th><th>Outcome</th><th class="num">Propagated in</th><th class="num">Room took</th><th>Evidence</th></tr></thead>
        <tbody>\(rows)</tbody></table>
        </section>
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
        let placed = Set(attributed.values.flatMap(\.self).map(\.message))
        let rest = failures.filter { !placed.contains($0.message) }

        guard !rest.isEmpty else {
            return ""
        }

        let rows = rest.map { failure in
            "<tr><td><span class=\"what\">\(escape(CellPhrase.sentence(for: failure.caseDisplayName ?? failure.testDisplayName ?? "unknown")))</span></td><td>\(escape(failure.message))</td></tr>"
        }
        .joined()

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
        """
    }

    ///
    /// What the run concluded about each room, by user.
    ///
    /// Computed once and handed to everything which draws it. The heat map and the table state the same verdict about the same cell, and the only way to keep them from drifting is for neither of them to work it out.
    ///
    /// - Parameters:
    ///     - rooms: The rooms of the run.
    ///     - failures: The failures of each room, by user.
    ///     - samples: The measurements, by cell.
    ///
    /// - Returns: The outcome of each room, by user.
    ///
    static func verdicts(rooms: [RoomManifest], failures: [String: [ReportedFailure]], samples: [String: [LatencySample]]) -> [String: CellOutcome] {
        var reached = [String: CellOutcome]()

        for room in rooms {
            let cell = room.cell ?? room.testName
            let measured = samples[cell]?.compactMap(\.duration).max() != nil

            reached[room.user] = CellOutcome.of(failures: failures[room.user] ?? [], wasMeasured: measured)
        }

        return reached
    }

    ///
    /// The exact identifier beneath a row, and the caption of its square.
    ///
    /// The cell where there is one, the test name where there is not, and the server beside it where the run deployed more than one.
    ///
    /// That last part is not cosmetic. Every live suite is parameterized over the servers under test, and no cell description carries a server token, so a run against a release and its predecessor writes every label on this page twice — the generated cells included — with nothing to say which half is which. It is also the axis a reader cares about most, because a defect which appears on one release and not the other is the whole reason the matrix has two.
    ///
    /// - Parameters:
    ///     - room: The room.
    ///     - namesServer: Whether the run deployed more than one server.
    ///
    /// - Returns: The identifier.
    ///
    static func identity(of room: RoomManifest, namesServer: Bool) -> String {
        let cell = room.cell ?? room.testName

        guard namesServer else {
            return cell
        }

        return "\(cell) · \(room.server.tag)"
    }

    ///
    /// The rules which hide what the filter is not asking for.
    ///
    /// Generated from ``CellOutcome/allCases`` rather than written out, so that a fifth outcome cannot reach the control without reaching the rules — an option which selects a value no rule matches empties the page and reads as a run of nothing.
    ///
    /// The selector is `tr.cell` and not `tbody tr`, which is the lesson this function exists to keep. The wider selector was shipped and it hid every row of the machine facts, of the legend which defines the four words the page is about, and of the table saying what else is in the directory — fourteen rows and five rows of content, deleted by choosing an option. A browser puts a bare `<tr>` into an implicit `<tbody>`, so "a row with no outcome" is every row on the page.
    ///
    /// - Returns: The rules.
    ///
    static func filterRules() -> String {
        CellOutcome.allCases
            .map { outcome in
                """
                body[data-filter="\(outcome.rawValue)"] tr.cell:not([data-outcome="\(outcome.rawValue)"]) { display: none; }
                body[data-filter="\(outcome.rawValue)"] .sq:not([data-outcome="\(outcome.rawValue)"]) { opacity: .14; }
                """
            }
            .joined(separator: "\n")
    }

    ///
    /// The sentence at the top of a row.
    ///
    /// A generated cell is phrased from its description, because the description names every axis and the suite's own display name is shared by every row of the quadrant.
    ///
    /// A hand-written one is the other way round, and this used to take the worse of the two. Those rooms have no cell, so the identifier was de-camel-cased and shown as the sentence — "Client to server atomic save" above "ClientToServer.atomicSave", the same words twice — while the room manifest already carried the sentence the suite's author wrote: "A file written the way applications write it arrives intact." It was being read for failures outside any room and nowhere else.
    ///
    /// - Parameters:
    ///     - room: The room.
    ///
    /// - Returns: The sentence.
    ///
    static func headline(of room: RoomManifest) -> String {
        guard let cell = room.cell else {
            return room.testDisplayName ?? CellPhrase.sentence(for: room.testName)
        }

        return CellPhrase.sentence(for: cell)
    }

    ///
    /// The identifier a square links to and a row answers on.
    ///
    /// Derived from the room's user, which is the one thing in a run that is unique per cell by construction — ``TestUserName/derive(from:ordinal:)`` makes it so in order that two runs of one parameterized test cannot share a File Provider domain.
    ///
    /// It is read back with `getElementById` rather than `querySelector`, because a user name carries full stops and a CSS selector would read those as class names.
    ///
    /// - Parameters:
    ///     - room: The room.
    ///
    /// - Returns: The identifier.
    ///
    static func anchor(of room: RoomManifest) -> String {
        "cell-\(room.user)"
    }

    ///
    /// Every cell of the run as one square, above the sections which describe them.
    ///
    /// A run is four hundred rows long and the question a reader opens it with — did this go well, and if not, where — is not a question four hundred rows answer. The squares answer it in one screen, keep the matrix's shape while they do it, and each one is a link to the row that says more.
    ///
    /// Grouped by quadrant and ordered within a group exactly as the section below orders its rows, so the nth square is the nth row. That correspondence is the whole reason the map is worth looking at: a column of red in one group says an axis value is broken, which no amount of scrolling would have said.
    ///
    /// The outcome is on each square as a data attribute rather than only as a colour, which is what lets the filter act on the map and the table through one rule, and what lets a reader who cannot separate the hues still get the pattern — the four outcomes differ in fill, in stripe and in border as well as in colour.
    ///
    /// - Parameters:
    ///     - quadrants: The rooms grouped, in the order the sections will take them.
    ///     - verdicts: The outcome of each room, by user.
    ///
    /// - Returns: The markup.
    ///
    static func heatMap(_ quadrants: [(key: String, value: [RoomManifest])], verdicts: [String: CellOutcome], namesServer: Bool) -> String {
        guard !quadrants.isEmpty else {
            return ""
        }

        var counts = [CellOutcome: Int]()
        var groups = ""

        for (quadrant, rooms) in quadrants {
            var squares = ""

            for room in rooms {
                let outcome = verdicts[room.user] ?? .notMeasured
                let caption = "\(identity(of: room, namesServer: namesServer)) — \(outcome.label)"

                counts[outcome, default: 0] += 1
                squares += "<a class=\"sq\" data-outcome=\"\(outcome.rawValue)\" href=\"#\(escape(anchor(of: room)))\" title=\"\(escape(caption))\"><em>\(escape(outcome.mark))</em><span>\(escape(caption))</span></a>"
            }

            // The heading the section below carries, with the raw key behind it. It was the other way round, which meant a block could not be matched to its section by eye.
            groups += "<div class=\"group\"><h3 title=\"\(escape(quadrant))\">\(escape(CellPhrase.heading(for: quadrant)))</h3><div class=\"squares\">\(squares)</div></div>"
        }

        let total = quadrants.reduce(0) { $0 + $1.value.count }
        var options = "<option value=\"\">every cell (\(total))</option>"

        // Only the outcomes this run actually produced. An option which matches nothing would empty the page and read as though the run had been empty.
        for outcome in CellOutcome.allCases where counts[outcome, default: 0] > 0 {
            options += "<option value=\"\(outcome.rawValue)\">\(outcome.label) (\(counts[outcome, default: 0]))</option>"
        }

        return """
        <h2>Every cell at once</h2>
        <p class="why">One square per cell, grouped by quadrant and ordered exactly as the sections below order their rows. Click one to jump to what it says. The filter narrows the sections too, and a quadrant none of whose cells match collapses to its heading and a count rather than vanishing, because a section which is not on the page cannot be told from a quadrant which never ran.</p>
        <div class="controls"><label for="outcome">Show</label><select id="outcome">\(options)</select><span id="shown" class="why"></span></div>
        <div class="map">\(groups)</div>
        """
    }

    ///
    /// The filter, and the end of the document.
    ///
    /// Vanilla and inline, because this page is zipped and sent to people who will not serve it, let alone build it. It does as little as it can: the hiding itself is a CSS rule keyed on one attribute of `body`, so filtering four hundred rows is one attribute write rather than four hundred style writes.
    ///
    /// What it cannot leave to CSS is the part a reader would otherwise misread. A quadrant none of whose cells match collapses to its heading and a count rather than disappearing — an absent section is indistinguishable from a quadrant which did not run, which is the same objection this project makes to excluding cells, and under a filter those headings reading zero are themselves the finding. The count beside each heading keeps its denominator, so it reads "one of eight cells" rather than "one cell", and the line beside the control says how much of the run is on screen whether or not anything is filtered.
    ///
    /// Without JavaScript the control does nothing and every cell stays visible, which is the right way round.
    ///
    /// - Parameters:
    ///     - total: How many cells the run has.
    ///     - quadrants: How many quadrants they fall into.
    ///
    /// - Returns: The markup.
    ///
    static func script(total: Int, quadrants: Int) -> String {
        """
        <script>
        (function () {
            var select = document.getElementById('outcome');
            var shown = document.getElementById('shown');

            if (!select) { return; }

            var sections = Array.prototype.slice.call(document.querySelectorAll('section.quadrant'));

            function apply() {
                var want = select.value;
                var cells = 0;
                var groups = 0;

                document.body.setAttribute('data-filter', want);

                for (var i = 0; i < sections.length; i++) {
                    var rows = sections[i].querySelectorAll('tr.cell');
                    var matched = 0;

                    for (var j = 0; j < rows.length; j++) {
                        if (!want || rows[j].getAttribute('data-outcome') === want) { matched++; }
                    }

                    // Collapsed rather than hidden. A section which is not on the page is indistinguishable from a quadrant which did not run, and under a filter the headings reading zero are the finding.
                    sections[i].classList.toggle('empty', matched === 0);
                    cells += matched;

                    if (matched > 0) { groups++; }

                    var pill = sections[i].querySelector('.pill.shown');

                    if (pill) {
                        var total = pill.getAttribute('data-total');
                        pill.textContent = want ? matched + ' of ' + total + ' cells' : total + (total === '1' ? ' cell' : ' cells');
                    }
                }

                shown.textContent = want
                    ? cells + ' of \(total) cells, in ' + groups + ' of \(quadrants) quadrants'
                    : '\(total) cells in \(quadrants) quadrants';
            }

            // A row the filter is hiding cannot be jumped to, so anything addressing one clears the filter first. That covers a square clicked while filtered and a #cell- link opened in a browser which restored the previous selection.
            function reveal(identifier) {
                var row = identifier ? document.getElementById(identifier) : null;

                if (!row || !select.value || row.getAttribute('data-outcome') === select.value) { return; }

                select.value = '';
                apply();
                row.scrollIntoView();
            }

            select.addEventListener('change', apply);

            document.addEventListener('click', function (event) {
                var square = event.target.closest ? event.target.closest('a.sq') : null;

                if (square) { reveal(square.getAttribute('href').slice(1)); }
            });

            apply();
            reveal(location.hash.slice(1));
        })();
        </script>
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
