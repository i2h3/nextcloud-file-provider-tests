// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import ServerHarness
import Testing

///
/// Content arrives when it is asked for, and only then.
///
/// A placeholder which is silently materialized costs a user their bandwidth and their disk; one which never materializes costs them their file. Both halves are therefore asserted separately, and the harness reads state through `stat` alone so that looking at an item never fetches it.
///
@Suite("Materialization", .requiresLiveEnvironment, .serialized, .timeLimit(.minutes(10)))
struct MaterializationTests {
    ///
    /// Sizes worth distinguishing: one that fits in anything, one that does not fit in a single request, and nothing at all.
    ///
    static let sizes = [0, 64 * 1024, 8 * 1024 * 1024]

    @Test(arguments: LiveEnvironment.servers, sizes)
    func `A file of any size arrives as a placeholder and materializes with its content intact.`(_ underTest: ServerUnderTest, _ size: Int) async throws {
        try await CleanRoom.with(underTest, testName: "Materialization.size\(size)") { room in
            let name = "payload-\(size).bin"
            let fingerprint = try await ServerWorkspace.withFixture(named: name, size: size, seed: 31) { source, fingerprint in
                try await room.server.upload(source, to: "/", force: true)

                return fingerprint
            }

            let file = room.localURL(of: name)

            try await Waiter.waitUntil("\"\(name)\" appears in the domain", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let placeholder = try #require(try LocalNode.at(file))
            #expect(placeholder.size == Int64(size))

            // An empty file has nothing to fetch, so the system has no reason to keep it dataless.
            if size > 0 {
                #expect(placeholder.isDataless, "A file which was never read should not already be on disk.")
                #expect(placeholder.allocatedBlocks == 0, "A placeholder should occupy no blocks.")
            }

            let started = ContinuousClock.now
            let arrived = try Materialization.materialize(file)
            MetricsRecorder.record("materialization", duration: ContinuousClock.now - started, in: room, test: "Materialization.size\(size)", payloadSize: Int64(size))

            #expect(arrived.count == size)
            #expect(ContentFactory.fingerprint(of: arrived) == fingerprint)

            // An empty file keeps the dataless flag after being read, and reasonably so: there was never anything to fetch, so nothing ever cleared it. Only a file with content proves that reading it brought the content down.
            if size > 0 {
                #expect(try LocalNode.at(file)?.isDataless == false)
            }
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Looking at a placeholder does not fetch it.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Materialization.lookingIsFree") { room in
            let name = "untouched.bin"

            try await ServerWorkspace.withFixture(named: name, size: 256 * 1024, seed: 32) { source, _ in
                try await room.server.upload(source, to: "/", force: true)
            }

            try await Waiter.waitUntil("\"\(name)\" appears in the domain", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let file = room.localURL(of: name)

            // Everything the harness does to inspect an item, done repeatedly. None of it may bring the content down.
            for _ in 0 ..< 5 {
                _ = try room.localChildren()
                _ = try LocalNode.at(file)
            }

            #expect(try LocalNode.at(file)?.isDataless == true, "Inspecting an item fetched it, which makes every assertion about materialization meaningless.")
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `A materialized file can be evicted and fetched again.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Materialization.eviction") { room in
            let name = "evictable.bin"

            let fingerprint = try await ServerWorkspace.withFixture(named: name, size: 512 * 1024, seed: 33) { source, fingerprint in
                try await room.server.upload(source, to: "/", force: true)

                return fingerprint
            }

            try await Waiter.waitUntil("\"\(name)\" appears in the domain", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let file = room.localURL(of: name)
            _ = try Materialization.materialize(file)
            #expect(try LocalNode.at(file)?.isDataless == false)

            #expect(Materialization.evict(file), "FileManager refused to evict the item.")

            // Eviction is asynchronous, and it does not settle all at once: the dataless flag has been observed to flip while the reported size was still catching up. All three properties of a placeholder are therefore awaited together rather than asserted the moment the flag appears.
            try await Waiter.waitUntil("\"\(name)\" is a placeholder of the full size again", timeout: LiveEnvironment.scaled(.seconds(60))) {
                guard let node = try LocalNode.at(file) else {
                    return false
                }

                return node.isDataless && node.size == 512 * 1024 && node.allocatedBlocks == 0
            }

            let evicted = try #require(try LocalNode.at(file))
            #expect(evicted.isDataless)
            #expect(evicted.size == 512 * 1024, "An evicted item should still report the size of the file it stands for.")
            #expect(evicted.allocatedBlocks == 0, "An evicted item should occupy no blocks.")

            // The point of evicting is being able to get it back.
            #expect(try ContentFactory.fingerprint(of: Materialization.materialize(file)) == fingerprint)
            #expect(try LocalNode.at(file)?.isDataless == false)
        }
    }

    @Test(arguments: LiveEnvironment.servers)
    func `Asking for a fetch without reading brings the content down.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Materialization.startDownloading") { room in
            let name = "requested.bin"

            try await ServerWorkspace.withFixture(named: name, size: 256 * 1024, seed: 34) { source, _ in
                try await room.server.upload(source, to: "/", force: true)
            }

            try await Waiter.waitUntil("\"\(name)\" appears in the domain", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == name }
            }

            let file = room.localURL(of: name)
            #expect(try LocalNode.at(file)?.isDataless == true)

            #expect(Materialization.startDownloading(file), "FileManager refused to start the download.")

            try await Waiter.waitUntil("\"\(name)\" has been fetched without being read", timeout: LiveEnvironment.scaled(.seconds(60))) {
                try LocalNode.at(file)?.isDataless == false
            }
        }
    }

    ///
    /// Whether a directory can be evicted at all, which decides fifty-six cells.
    ///
    /// The matrix asks for `item:evicted` on folders and packages as readily as on files, and the harness refuses all of it: ``ScenarioWorld`` throws "an evicted folder, because eviction applies to content and a directory has none of its own". That is the single largest reason phase A is 350 cells and not 406 — every one of the fifty-six it cannot build asks for exactly this, and none of them asks for the sharing and group folders the remainder was assumed to be waiting on.
    ///
    /// The refusal is a claim, and it has never been checked. `FileManager.evictUbiquitousItem(at:)` is not documented as file-only, `SF_DATALESS` on a directory encodes whether its contents have been fetched — this suite's own oracle says so — and a package is presented to the system as a single item, which is the whole reason packages are not excluded elsewhere. So one of three things is true, and a run settles which: the system refuses, and the exclusion is right for a reason worth writing down; or it accepts and the directory reports itself dataless, and fifty-six cells are buildable; or it accepts and nothing changes, which is the worst of the three and the one silently assuming either answer would hide.
    ///
    /// Recorded rather than asserted, deliberately. There is no contract here that says what must happen, so a cell demanding either answer would be this suite inventing one — and this is the second time that matters in this file, after a zero-byte file turned out to keep its dataless flag because there was nothing to fetch.
    ///
    @Test(arguments: LiveEnvironment.servers)
    func `Whether a directory can be evicted is recorded rather than assumed.`(_ underTest: ServerUnderTest) async throws {
        try await CleanRoom.with(underTest, testName: "Materialization.directoryEviction") { room in
            let folder = "evictable"
            let child = "inside.bin"

            try await room.server.createDirectory("/\(folder)")
            _ = try await room.waitForRemoteEntry(named: folder)

            try await ServerWorkspace.withFixture(named: child, size: 64 * 1024, seed: 37) { source, _ in
                try await room.server.upload(source, to: "/\(folder)", force: true)
            }

            _ = try await room.waitForRemoteEntry(named: child, in: "/\(folder)")

            let url = room.localURL(of: folder)

            try await Waiter.waitUntilBlocking("\"\(folder)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren().contains { $0.name == folder && $0.kind == .directory }
            }

            // Fetched first, because evicting something which was never materialized would answer a different question.
            let childURL = url.appending(path: child, directoryHint: .notDirectory)

            try await Waiter.waitUntilBlocking("\"\(child)\" reaches the client", timeout: LiveEnvironment.scaled(.seconds(180))) {
                try room.localChildren(of: folder).contains { $0.name == child }
            }

            _ = try Materialization.materialize(childURL)

            let fetched = try #require(try LocalNode.at(childURL))

            #expect(!fetched.isDataless, "The child did not materialize, so this trial cannot say anything about evicting its folder.")

            let accepted = Materialization.evict(url)

            guard accepted else {
                ScenarioOracle.observe("""
                the system refused to evict the folder "\(folder)", so `item:evicted` on a directory is not a state this harness can establish and the fifty-six cells asking for it stay unbuildable for a reason rather than an assumption
                """, in: room)

                return
            }

            // Accepted is not the same as done. What matters is what the folder and its child report afterwards, and only one of the two would make those cells buildable.
            let folderNode = try #require(try LocalNode.at(url))
            let childNode = try #require(try LocalNode.at(childURL))

            ScenarioOracle.observe("""
            the system accepted evicting the folder "\(folder)": afterwards the folder reads as \(folderNode.isDataless ? "dataless" : "not dataless") and its fetched child as \(childNode.isDataless ? "dataless, so the content really was dropped" : "still materialized, so the call was accepted and changed nothing"). \
            \(folderNode.isDataless || childNode.isDataless ? "The state can be established, and the fifty-six cells excluded for it are excluded wrongly." : "The state cannot be confirmed, which is the answer that would have been hidden by assuming either of the other two.")
            """, in: room)
        }
    }
}
