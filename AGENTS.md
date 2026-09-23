#  AGENTS.md

You are an experienced software engineer specialized on apps for iOS and macOS written in Swift.

## Repository Structure

- `Sources/ClientHarness/` observes and controls the desktop client on this machine: its lifecycle, the File Provider domains it registers, the inspection of those domains, waiting, diagnostics and preflight. It deliberately depends on neither Docker nor a Nextcloud server, which is what keeps its own tests hermetic.
- `Sources/ScenarioMatrix/` is the axis model the end-to-end suites enumerate their cases from: what an item can be, what state it can be in, where it can live, what can be done to it, and which combinations cannot exist. It is pure data with **no imports at all**, not even Foundation, and that is load-bearing rather than incidental — it describes what should be tested with no knowledge of how any of it is established, so a constraint can never come to be justified by what the harness currently happens to support. One type per file, as everywhere else.
- `Sources/ServerHarness/` deploys and provisions the Nextcloud servers under test: containers, per-test users, app passwords and fixture content.
- `Sources/Runner/` is the `tests` executable, the command line entry point which owns the containers and the machine-level client reset around a single test process.
- `Tests/ClientHarnessTests/` and `Tests/ServerHarnessTests/` are hermetic unit tests of the harness itself.
- `Tests/FileProviderTests/` holds the end-to-end suites, in `Suites/`, with their shared machinery in `Support/`. They are gated on a live environment and skip themselves without one. `Support/CleanRoom.swift` builds the per-test user, client configuration and File Provider domain; `Support/ServerWorkspace.swift` is the half of it which needs no client. `Support/ScenarioWorld.swift` is the other half of the axis model: it puts a real client and server into the state a cell describes and then verifies that it did, and `Support/ScenarioOracle.swift` judges what happened to it — including declining, by name and with a reason, the clauses this harness cannot observe. `Support/ScenarioSelection.swift` decides which cells a quadrant runs and names why it holds any back; `Support/KnownLimitation.swift` carries the failures the client is known to produce, so that those cells run rather than being excluded.
- `README.md` is the only prose document of this repository. Machine setup, how to run, artifacts and troubleshooting all live there.

## Code Style

- This project is set up to use SwiftFormat.
- The `Package.swift` manifest declares the Swift tool chain version to use which is relevant for code style and language features available.
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Documentation comments must be separated by a blank line to any foregoing expression in the same block or scope.
- Never wrap arguments in func declarations or calls.
- Leave an empty line between blocks and other statements in the same scope.
- Instead of declaring multiple values in a single guard-let statement, write one dedicated guard-let statement per value.
- Always run `swiftformat .` after applying changes. The tool is expected to be installed in the environment; the package does not vend it as a plugin.

## Testing Instructions

- Run `swift test` in the repository root directory. This runs the hermetic harness tests and must stay green on any Mac, including one without Docker, without the desktop client and without Full Disk Access.
- The end-to-end suites need deployed servers and a configured client. They are run with `swift run tests` and report themselves as skipped under a bare `swift test`.
- `swift run tests doctor` reports whether a machine can run the end-to-end suites and what a run would remove, without changing anything.
- `swift run tests prepare` deploys the servers and leaves them running, so the suites can be started from Xcode with the debugger attached; `swift run tests teardown` removes what it left behind. See the "Running from Xcode" section of the `README.md`.
- A failed run drafts a bug report per failure into `Artifacts/<run>/reports/`, and `swift run tests report` does the same for any run on demand. Every section is filled from what the run recorded; nothing is left as a placeholder. The drafts are never committed and never filed: read one, then post it yourself.
- The title of a drafted report is taken from the comment written beside the failing expectation, so writing a good comment there is also writing a good bug title.
- A suite whose cases come from `ScenarioMatrix` can quietly run fewer of them, or none, without any test failing — a filter that stops matching, an axis value renamed, a constraint that prunes more than it did. `Tests/FileProviderTests/Suites/ScenarioSelectionTests.swift` therefore asserts the exact rows each generated suite runs and the count it does not run yet. Changing either is a deliberate edit to that file with a diff to read.
- Never assert an invariant this harness cannot observe. A clause which cannot fail is worse than a missing one, because it reports as coverage: "exactly one item per name" cannot fail against a POSIX listing, and an evicted item is currently indistinguishable from a placeholder by every signal available. Decline such a clause by name and say why.
- A run produces three kinds of statement and they must not be confused. An **expectation** says what had to hold. A **decline** says a clause could not be judged here, named and with its reason, because a clause quietly missing from an evaluation is indistinguishable from one that passed. An **observation** says which of several permitted results happened, where the specification permits more than one and demanding either would fail on a reasonable machine — a volume which holds two names differing only in case, a conflict resolved by keeping a copy. Observations and declines are attached to the run, never only printed: a run whose evidence lives in terminal scrollback cannot be compared with the next one.
- Never exclude a cell because the client does not support what it asks for. Cells run, and a failure the client is known to produce is registered as expected through `Support/KnownLimitation.swift`, which scopes it to exactly the cells it covers and cites the upstream issue. Excluding them instead hides the day support arrives, and leaves nobody to notice that a feature is untested — the exclusion is by construction invisible, which is the whole objection to it. `Support/ScenarioSelection.swift` excludes a cell only when this harness cannot *build* the world it describes, and every such exclusion returns the reason as a sentence rather than a boolean, so the remainder is countable by cause instead of being one opaque number.
- A run is destructive to whatever Nextcloud account is configured on the machine. It asks before removing anything unless `FPT_ALLOW_DESTRUCTIVE=1` is set.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Facts about the desktop client, the File Provider framework or the operating system must be verified against the installed build or the SDK before they are written down, not recalled.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check the `./README.md` for validity and update, if necessary.
- Semantic versioning is used. Report on the impact in this regard after applying changes.

## Commit Instructions

- Never commit automatically.
- Suggest commit title and description.
- If the changes relate to a specific issue, mention the issue number in the title.

## Pull Request Instructions

- Never open a pull request automatically.
- Suggest a concise pull request description.
- If the changes relate to a specific issue, mention the issue number in the title.
