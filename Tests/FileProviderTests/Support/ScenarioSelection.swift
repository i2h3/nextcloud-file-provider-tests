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
    /// The cells a suite runs, in the order it should run them.
    ///
    /// Sorted by description, as they always were, except that a cell whose failure is a known limitation of the client goes last. That is not tidiness. A cell which is expected to fail spends its whole timeout failing and leaves the client in whatever state that produces, and the next cell inherits it — which was not hypothetical: `kind:bundle` sorts before `kind:file`, so a package cell ran immediately before an empty-file cell in every single run, and when the second one failed there was no way to tell whether the client had lost the creation or the package cell had poisoned the room.
    ///
    /// A confound which is structural cannot be measured away by repeating the run. Moving the expected failures to the end removes it for every quadrant at once, and costs nothing: the cells still all run.
    ///
    /// - Parameters:
    ///     - quadrant: The quadrant to take the cells of.
    ///
    /// - Returns: The buildable cells, ordered.
    ///
    static func cells(of quadrant: Quadrant) -> [Scenario] {
        Generator
            .scenarios(for: quadrant, phase: .a)
            .filter(isBuildable)
            .sorted { first, second in
                let firstIsKnown = KnownLimitation.reason(for: first.description) != nil
                let secondIsKnown = KnownLimitation.reason(for: second.description) != nil

                guard firstIsKnown == secondIsKnown else {
                    return !firstIsKnown
                }

                return first.description < second.description
            }
    }

    ///
    /// Whether this harness can build the world a cell describes and judge what happens in it.
    ///
    /// - Parameters:
    ///     - scenario: The cell.
    ///
    /// - Returns: `true` if it can be run today.
    ///
    static func isBuildable(_ scenario: Scenario) -> Bool {
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
    private static func isBuildable(_ realization: Realization, kind: ItemKind) -> Bool {
        realization.levels.allSatisfy { level in
            switch level {
                case .dataless, .materialized:
                    true

                case .evicted:
                    // Established by fetching and dropping the content. The two states remain indistinguishable to a test process — the same flag, size and zero blocks — so the cell runs and the distinction alone is declined, rather than the cell being dropped for a clause it cannot judge.
                    kind == .file

                case .materializedDeep:
                    // One level down, child by child, which is the only way there is: asking the system to download a directory materializes its immediate children and stops. The model emits this level only where it differs from a shallow one.
                    kind == .folderWithChildren

                case .unknown:
                    // Every container a cell can place sits under the domain root, which is enumerated once while the room is built. A subdirectory container is therefore dataless at the start of a test and never unknown.
                    false
            }
        }
    }
}
