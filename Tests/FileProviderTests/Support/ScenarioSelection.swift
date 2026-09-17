// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ScenarioMatrix

///
/// Which cells of the model this harness can currently establish and judge.
///
/// One filter for every generated suite, rather than a copy per quadrant. The list of what is missing is a property of the harness and not of any one quadrant, so keeping it in one place means building a primitive turns its rows on everywhere at once — and means the count of what is still excluded cannot drift apart between suites.
///
/// Every exclusion here is a **named, countable primitive that does not exist yet**, never a cell judged uninteresting. That distinction is the reason the filter is written as a list of blockers rather than as a list of what to include: an included-list quietly stops mentioning what it leaves out.
///
enum ScenarioSelection {
    ///
    /// Whether this harness can build the world a cell describes and judge what happens in it.
    ///
    /// - Parameters:
    ///     - scenario: The cell.
    ///
    /// - Returns: `true` if it can be run today.
    ///
    static func isBuildable(_ scenario: Scenario) -> Bool {
        // A package needs a fixture builder, and nothing in this repository creates one.
        guard scenario.item.kind != .bundle else {
            return false
        }

        // Above the chunking threshold the upload takes a different path through the client, and nothing here has ever exercised it.
        guard scenario.item.size != .large else {
            return false
        }

        // An empty file is perfectly constructible, and is excluded for a narrower reason than the rest of this list: it keeps its dataless flag after being read, because there was never anything to fetch to clear it, so the realization clause cannot fail for it. The cell is buildable and the oracle is not, which is a different problem from the others here and wants a per-cell decline rather than an exclusion. Recorded as a blocker so the count stays honest until that exists.
        guard scenario.item.size != .empty else {
            return false
        }

        // Reading the local-name bounce needs an extended-attribute reader this harness does not have.
        guard scenario.encoding == nil else {
            return false
        }

        // A pin can be neither set nor read from a test process, so a cell asking for one cannot be established.
        guard scenario.contentPolicy == .default else {
            return false
        }

        // Sharing and group folders need provisioning through OCS and the groupfolders application, neither of which this harness speaks.
        guard scenario.site.placements.allSatisfy({ $0.container.type == .standard }) else {
            return false
        }

        return isBuildable(scenario.realization, kind: scenario.item.kind)
    }

    ///
    /// Whether this harness can put an item into the state a cell asks for.
    ///
    /// - Parameters:
    ///     - realization: What the cell asks for.
    ///     - kind: What sort of item it is.
    ///
    /// - Returns: `true` if the state can be established and confirmed.
    ///
    private static func isBuildable(_ realization: Realization, kind _: ItemKind) -> Bool {
        realization.levels.allSatisfy { level in
            switch level {
                case .dataless, .materialized:
                    true

                case .evicted:
                    // Measured: an evicted item and a never-fetched placeholder present an identical `(isDataless, size, allocatedBlocks)` triple, so a cell asserting the difference could not fail. Excluded until something separates them.
                    false

                case .materializedDeep:
                    // Needs a recursive materialization walk, which this harness deliberately does not have — there is no recursive descent anywhere in it.
                    false

                case .unknown:
                    // Every container a cell can place sits under the domain root, which is enumerated once while the room is built. A subdirectory container is therefore dataless at the start of a test and never unknown.
                    false
            }
        }
    }
}
