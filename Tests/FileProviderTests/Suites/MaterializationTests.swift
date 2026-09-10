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

            let placeholder = try #require(LocalNode.at(file))
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
                #expect(LocalNode.at(file)?.isDataless == false)
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
                _ = LocalNode.at(file)
            }

            #expect(LocalNode.at(file)?.isDataless == true, "Inspecting an item fetched it, which makes every assertion about materialization meaningless.")
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
            #expect(LocalNode.at(file)?.isDataless == false)

            #expect(Materialization.evict(file), "FileManager refused to evict the item.")

            // Eviction is asynchronous, and it does not settle all at once: the dataless flag has been observed to flip while the reported size was still catching up. All three properties of a placeholder are therefore awaited together rather than asserted the moment the flag appears.
            try await Waiter.waitUntil("\"\(name)\" is a placeholder of the full size again", timeout: LiveEnvironment.scaled(.seconds(60))) {
                guard let node = LocalNode.at(file) else {
                    return false
                }

                return node.isDataless && node.size == 512 * 1024 && node.allocatedBlocks == 0
            }

            let evicted = try #require(LocalNode.at(file))
            #expect(evicted.isDataless)
            #expect(evicted.size == 512 * 1024, "An evicted item should still report the size of the file it stands for.")
            #expect(evicted.allocatedBlocks == 0, "An evicted item should occupy no blocks.")

            // The point of evicting is being able to get it back.
            #expect(try ContentFactory.fingerprint(of: Materialization.materialize(file)) == fingerprint)
            #expect(LocalNode.at(file)?.isDataless == false)
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
            #expect(LocalNode.at(file)?.isDataless == true)

            #expect(Materialization.startDownloading(file), "FileManager refused to start the download.")

            try await Waiter.waitUntil("\"\(name)\" has been fetched without being read", timeout: LiveEnvironment.scaled(.seconds(60))) {
                LocalNode.at(file)?.isDataless == false
            }
        }
    }
}
