# Nextcloud File Provider Tests

End-to-end tests for the macOS File Provider implementation of the
[Nextcloud desktop client](https://github.com/nextcloud/desktop), run against real Nextcloud
servers deployed on demand as local Docker containers.

## Purpose

A test here drives the **signed, distribution build** of the client installed at
`/Applications/Nextcloud.app`, configures it through its own command line options, and then compares
two independent accounts of the same state:

- what the server says, read over WebDAV and OCS with [Rainmaker](https://github.com/i2h3/rainmaker),
- what the client says, read from its File Provider domain under `~/Library/CloudStorage` with
  `stat` and `readdir`.

Deliberately out of scope: the classic synchronisation folders, everything which is only reachable
through a window or a Finder menu, and every platform other than macOS.

Since version 34 the client is **App Sandboxed**, so its configuration, logs and caches live inside
`~/Library/Containers/com.nextcloud.desktopclient/Data/` rather than where an unsandboxed application
would keep them. A path outside that container is not writable by the client at all, which is why the
harness never passes it one.

The test process cannot use `NSFileProviderManager` — the framework reserves it for the provider's
own app and its sibling extensions — so there is no `waitForChanges`, no `signalEnumerator` and no
manual scheduling. Every wait is a condition poll against a deadline, and materialization state is
read from the `SF_DATALESS` flag in `st_flags`.

### Cases that are generated rather than written

Most suites here are written by hand, and each of them varies one thing — which server it talks to —
while pinning everything else to whatever the author happened to pick: a file, at the root, already
materialized, of one size. Those choices are invisible, so what they leave untested is invisible too.

`Sources/ScenarioMatrix/` makes them explicit. It is an axis model — what an item can be, what state
it can be in, where it lives, what is done to it, where the change originates — together with the
rules that prune combinations which cannot exist, such as editing the bytes of a file whose content
was never downloaded. It enumerates cells; it knows nothing about how any of them is established,
and it has no imports at all, not even Foundation, so it cannot acquire that knowledge by accident.

`Support/ScenarioWorld.swift` is the half it does not have: it puts a real client and a real server
into the state a cell describes, and then checks that it did. `Support/ScenarioOracle.swift` judges
what happens next, and **declines by name the clauses it cannot observe** — an assertion which cannot
fail is worse than a missing one, because it reports as coverage.

A generated suite has a failure mode a hand-written one does not: the set of cases can shrink to
nothing without a single test failing. `Suites/ScenarioSelectionTests.swift` therefore pins the exact
rows each generated suite runs, and counts the ones it does not run yet.

## Machine setup

The client under test is installed at `/Applications/Nextcloud.app` from its signed disk image and
launched once by hand, so that Gatekeeper is satisfied and the File Provider extension is registered
and approved. The location is not configurable: app extensions are not reliably loaded from anywhere
else, and a copy elsewhere would not imitate a real installation.

Also needed:

- Docker Desktop or OrbStack, running.
- **Full Disk Access** for whichever application starts the run — in practice the terminal — followed
  by a restart of it, because a privacy grant only applies to a newly launched process. This is not
  optional, and it is not merely about reading files: without it macOS asks whether the application
  may access files managed by Nextcloud, suppresses the repeats, and then answers later reads with
  `Operation not permitted` and no dialog at all. With it, a domain is read silently and a run needs
  nobody at the keyboard. Preflight checks it by reading a genuinely protected path, so
  `swift run tests doctor` will tell you.

  The service is `kTCCServiceFileProviderDomain`, which is not Full Disk Access and not the
  "Files and Folders" group in System Settings — those are the `SystemPolicy*` services. Its grant is
  keyed by a *triple*: the service, the reading application, and the **provider domain**. A provider
  reading its own domains is granted automatically because the bundles match, which is why the client
  never prompts and this harness does: the reader is a different bundle, inherently.

  `~/Library/CloudStorage` *itself* lists without any grant — protection resolves path to domain, and
  the parent resolves to no domain — which is why an early version of this check passed on a machine
  that then failed every test.

  On macOS 27 and later this grant also covers the client's own application data, which that release
  began guarding separately with `kTCCServiceSystemPolicyAppDataDetailed` for a hardcoded list of
  applications in `/usr/libexec/sandboxd` — a list naming both `com.nextcloud.desktopclient` and its
  group container `NKUJUXUJ3B/com.nextcloud.desktopclient`. Those are where this suite reads
  `nextcloud.cfg` and the extension's per-domain logs, so a refusal would cost it the configuration
  and all of its evidence. Measured on 27.0 (26A428): Full Disk Access alone satisfies it, and no
  second grant is asked for. It is checked separately anyway, because the two were not known to be
  one grant and a future release may separate them again.

  The refusal has a shape worth knowing, because it is not the one a missing file has: the container
  can still be *looked up* and its directories still appear, while every read of anything inside them
  answers `Operation not permitted`. A check asking whether a path exists passes throughout.
  `swift run tests doctor` reports this separately, as *Client data*.

  The same release moved the per-user privacy database out of
  `~/Library/Application Support/com.apple.TCC/` into `/private/var/containers/Data/ProtectedSystem/`,
  where Full Disk Access does not reach it either. It had been this project's Full Disk Access probe,
  and when it vanished the check reported a machine that held the grant as one that did not. Probes
  now report *absent* separately from *refused*, and there is more than one of them.

  A read of a domain has four outcomes, and telling them apart is the whole job:

  | | |
  | --- | --- |
  | Granted | the read succeeds |
  | Explicitly denied | `NSCocoaErrorDomain` 257 with an underlying `EPERM`, loudly |
  | Never asked, and the reader cannot be prompted | **the read parks indefinitely** |
  | Granted but the provider has not populated or authenticated yet | an empty listing, legitimately |

  The third is the dangerous one and it is the *default* for a fresh domain under an unattended
  runner: a client with no `NSFileProviderDomainUsageDescription` cannot be shown the prompt, so the
  access request is never resolved and the read neither returns nor fails. That is why every wait in
  this harness carries its own deadline and abandons the thread rather than waiting on it — see
  `Deadline`. An empty listing is not a permission problem and is a state to wait on.

  There is **no non-interactive way to pre-grant this**: `tccutil` has only a `reset` verb, and the
  service does not appear in the configuration-profile surface where PPPC payloads are defined. Full
  Disk Access is what makes unattended runs work in practice — with it granted to the terminal, this
  suite creates over a hundred fresh domains in a run and is never prompted once, which is also the
  evidence that the grant covers every domain rather than being consulted per domain.

  That makes the manual grant a deployment requirement rather than a convenience, and the reason is
  structural. A SwiftPM test bundle has no `Info.plist` at all, so it cannot declare
  `NSFileProviderDomainUsageDescription`; a reader which cannot declare it cannot be prompted; and a
  request which cannot be prompted is never resolved. The obvious remedy — adding the key — is not
  reachable without changing how the bundle is built. Somebody granting Full Disk Access by hand,
  once, is what makes this suite runnable at all, and it is invisible from the code.
- Enough free disk space for container images and materialized fixtures.

A developer machine is explicitly supported for writing and debugging these tests. The destructive
steps print what they found and ask before removing anything, and they keep a copy of the existing
configuration in the artifacts directory.

For long runs, give the suite a machine of its own — a dedicated Mac, a dedicated macOS user,
or a macOS virtual machine — with auto-login, no screen lock or screen saver, Focus switched on,
`caffeinate -dimsu` for the duration of the run, Spotlight indexing of the domain switched off, and
no personal Nextcloud account on that login. Keep Finder away from the domain: it materializes files
to draw previews. In a virtual machine, keep Docker inside the same machine so that the addresses the
client sees are the ones the tests use.

The full matrix is not run by continuous integration and is not meant to be. It needs Docker, a
logged-in graphical session, the signed client installed at `/Applications/Nextcloud.app` and a
privacy grant given by hand, and it is destructive to whatever account is configured on the machine
it runs on. Hosted macOS runners have none of that. So a full run is something a person starts, on
their own machine or in a virtual machine, and the only thing continuous integration does here is
build the package and run the hermetic tests.

## Running

Hermetic unit tests of the harness itself, which need no server, no client and no Docker:

```bash
swift test
```

The live suites report themselves as skipped there. They are run through the runner, which deploys
the servers, resets the client, runs one test process against the whole matrix, and tears everything
down again:

```bash
swift run tests
```

```bash
swift run tests --tags latest --filter DomainLifecycleTests
```

`--filter` is a regular expression matched against the name of the test *type*, such as
`ConflictTests`, not against the name a suite is given for display. A filter which matches nothing
fails the run rather than reporting a clean pass over an empty suite.

```bash
swift run tests doctor
```

```bash
swift run tests reset
```

`doctor` changes nothing: it reports whether the machine is ready and what a run would remove.
`prepare` and `teardown` are the two halves of a run without the test process in between, for
debugging from Xcode — see *Running from Xcode*.

The matrix is not written down anywhere. `latest` is deployed first and asked which release it is,
and the major before that becomes the other half — a server reporting `34.0.3` gives a matrix of
`latest` and `33`. That matches the support policy of one current release plus its predecessor, and
it means no file in this repository has to be edited when a server release ships. The day a 35 is
published, the same code tests 35 and 34.

Both halves are recorded as they were found: a server's descriptor carries the version it reported
alongside the tag it was deployed under, because `latest` is a moving target and two runs weeks apart
under the same tag may well have tested different releases.

Useful options of the run: `--tags` names the releases explicitly and switches the derivation off, `--with-push` deploys every release a second
time with the High Performance Backend for Files, `--filter` is passed on to the test process,
`--keep-containers` leaves the servers up for investigating a failure, `--no-client-reset` leaves the
desktop client on this machine untouched (for suites which need no client, such as the server
provisioning ones), `--allow-development-client` accepts a client the system policy rejects, and
`--artifacts` chooses where everything is collected.

The subject is normally the notarized build a user installs, and preflight refuses anything else. A
development build has to be testable too — that is how a fix is verified before it is released — so
`--allow-development-client` accepts one, and the report says so in the words "not the build a user
would install" rather than quietly passing.

The environment the runner passes to the test process, should a run need to be reproduced by hand:

| Variable | Meaning |
| --- | --- |
| `FPT_MATRIX` | JSON array describing the servers under test, including the version each reported |
| `FPT_MATRIX_FILE` | A file holding that same JSON, used when `FPT_MATRIX` is unset |
| `FPT_ARTIFACTS_DIR` | Where logs, attachments and reports are collected. Defaults to the directory of `FPT_MATRIX_FILE` |
| `FPT_TIMEOUT_SCALE` | Factor applied to every timeout, for slow machines |
| `FPT_ALLOW_DESTRUCTIVE` | Approves the removal of an existing client configuration up front |
| `FPT_ALLOW_UNNOTARIZED_CLIENT` | Accepts a client the system policy rejects, such as a development build |

## Running from Xcode

Worth the setup, because the reason to run a suite from Xcode is the debugger, and a breakpoint
inside a test which is waiting on a File Provider is worth a great deal when the client does
something nobody predicted. The client under test is a separate, signed application either way, so
nothing about debugging the tests changes what is being tested.

Xcode cannot deploy the containers, so that half is done first and left running:

```bash
swift run tests prepare --tags latest --allow-development-client
```

That resets the client, deploys the servers, writes `Artifacts/session/matrix.json` and prints the
three variables to set. Open `Package.swift` in Xcode, then Product, Scheme, Edit Scheme, Test,
Arguments, and add:

| Variable | Value |
| --- | --- |
| `FPT_MATRIX_FILE` | the absolute path `prepare` printed |
| `FPT_ALLOW_DESTRUCTIVE` | `1` |
| `FPT_ALLOW_UNNOTARIZED_CLIENT` | `1` |

None of the three change between sessions. The ports do — they are assigned when the containers
start — which is exactly why the scheme points at a file instead of carrying the matrix itself:
`prepare` rewrites the file and the scheme keeps working.

Two settings which are not optional:

- **Full Disk Access for Xcode**, followed by quitting and reopening it. A privacy grant applies only
  to a newly launched process, and without it reads inside a domain are refused with
  `NSCocoaErrorDomain` 257.
- **Parallel execution off**, in the same scheme under Test, Options. There is one desktop client and
  one File Provider domain on the machine, so the suites cannot run at once. A clean room refuses to
  be built while another one stands and says so, rather than letting the two corrupt each other.

Then run the tests as usual. Afterwards:

```bash
swift run tests teardown
```

A prepared session is otherwise indistinguishable from a run: the same clean rooms, the same
per-test users, the same artifacts. What it does not do is delete the containers, which is what
`teardown` is for and why `prepare` writes down what it deployed.

## What has been measured

Across four servers on one machine, `latest` being 34.0.3 and the derived predecessor 33.0.8. The
`latest` tag has since moved to 35.0.0, so these figures describe the releases named here rather than
whatever `latest` resolves to today — which is why a run records the version each server *reported*
and not the tag it was asked for:

| Measurement | Plain | With the High Performance Backend |
| --- | ---: | ---: |
| Server to client propagation | 9.0–29.0 s | **0.83–0.87 s** |
| Client to server propagation | 0.38–1.01 s | 0.26–0.45 s, once 11.1 s |
| Materialization of 8 MiB | 0.65–0.79 s | 0.65–0.73 s |
| Building one clean room | 7–15 s | 7–15 s |

The two releases behave the same. Nothing measured here separates 33.0.8 from 34.0.3 beyond the
noise the numbers already carry, which is the answer one wants from the older half of the matrix.

The one slow number is the client polling for server-side changes, and `notify_push` removes it
almost entirely — a factor of thirty on the direction which dominates the run time. Both
configurations are worth testing, because both are deployed in the wild; `--with-push` adds the second
one. Waits for anything the server originates are given three minutes, which is generous against the
29 s baseline rather than optimistic.

That baseline does not behave like a delay drawn from a polling interval. Five measurements have
produced 9.0, 29.0, 29.0, 9.2 and 28.8 seconds: two clusters, not a spread. A change landing at a
uniformly random point of a fixed interval would fill the range between them, so something is
quantizing it, and the earlier guess that the measurement is simply phase-locked to a clean room
taking a constant time does not explain two attractors. It is recorded here as an observation rather
than explained, because the explanation is not known. What can be said is that the figure is a
property of this suite's timing as much as of the client, and it should be read as an upper bound
rather than as a delay a user would typically see.

One measurement is unexplained and is written down so that a second sighting is recognisable rather
than surprising: on `latest+push`, client to server propagation was **11.1 s**, against 0.45 s for
`33+push` in the same run and 0.26–0.44 s for `latest+push` in every earlier one. Uploading should
not depend on the push backend at all, since that carries notifications in the other direction. Four
containers and their Redis sidecars were up at once, so contention is the innocent reading — but it
does not account for `33+push` being unaffected under the same load. One sample, so it is not yet a
finding.

An empty file is worth one note: it keeps the `SF_DATALESS` flag after being read, because there was
never anything to fetch. Only a file with content proves that reading it brought the content down.

Eviction is asynchronous and does not settle all at once: the dataless flag has been observed to flip
while the reported size was still catching up. All three properties of a placeholder are therefore
awaited together rather than asserted the moment the flag appears.

## How names are spelled

Measured on `latest`, with and without push. The two sides of a synchronised file do not spell names
the same way, and they are consistent about it:

| Direction | Written as | Ends up as |
| --- | --- | --- |
| Server to client | `Übung.txt` precomposed (`U+00DC`) | decomposed (`U+0055 U+0308`) |
| Client to server | `éclair.txt` decomposed (`U+0065 U+0301`) | precomposed (`U+00E9`) |

One policy explains both: **the wire format is precomposed, the local file system hands out
decomposed.** The round trip is stable and lossless — a name written decomposed is stored
precomposed and read back decomposed, and it is the same file throughout.

So this is asserted rather than tolerated. Recording it as a known issue would have been the wrong
call: there is nothing here waiting to be fixed, and the assertions catch the regression that would
actually cost users something — a client putting a decomposed name on the wire, where every Windows
and Linux client of the same account would see a file it has no reason to consider the same one.
Each direction therefore checks three things: that the two spellings are canonically the same name,
that the spelling is the expected normalization form, and that the item exists exactly once on each
side. The last one is checked on the server *after* the name has been enumerated locally, because
that is when a client which compares names by their bytes decides the file is missing and uploads a
duplicate.

Names which cost nothing either way, and are in the suite to prove it: an emoji with a variation
selector, a name with no extension, and a 180-character name.

## Artifacts

Each run writes to `Artifacts/<timestamp>/`. The directory is deliberately not hidden — a run leaves
real evidence behind and real disk behind it, and neither should be invisible. It is git-ignored, and
that matters for more than tidiness: a run's logs describe client defects which have not been
reported yet, and this repository is public.

The directory holds:

- `index.html` — the run's front page, and the one artifact meant to be read rather than parsed. One
  row per cell, grouped by quadrant, each saying in a sentence what the cell did and how it went, with
  the technical identifier underneath as a footnote and a link into that cell's logs. Outcomes have a
  legend, because *no measurement* means nothing to anyone who did not write it. What a cell saw but
  was not entitled to assert — which name a colliding pair settled on, which version won a conflict —
  appears beneath its row, on passing cells as much as failing ones.
- `reports/` — a drafted bug report per defect. See *When a test finds something*.
- `run.json` — what the run was: the client, the servers and the releases they actually reported, the
  preflight checks, the flags it was started with, and the machine's time zone. The zone is not
  incidental — the File Provider extension timestamps its log in local time and never says which,
  so reading that log later is impossible without it.
- `events.jsonl` — everything the test process recorded, one event per line. The only artifact which
  says *which* case of a parameterized test failed and *when*, which is what ties a failure to the
  clean room it happened in. Written by an undocumented option, so `--no-event-stream` turns it off
  and a report degrades to the xUnit file without it.
- `results-swift-testing.xml` — JUnit. One entry per test function with its total duration, which is
  thinner than it sounds: a parameterized test is a single entry, and neither the server release nor
  the other arguments appear in it. It answers "did the run pass", not "which case failed".
- `attachments/` — diagnostics bundles, recorded measurements, and observations: the things a cell
  saw and is not entitled to assert. A clause whose specification permits more than one result is
  recorded rather than judged, and recording it in a terminal would mean two runs a month apart could
  not be compared.
- `clean-rooms/<user>/room.json` — which test the room belonged to, which cell of the matrix it was,
  which server it ran against, and when it began and ended. A room's directory is named after the
  Nextcloud user it created, and that name has no relation to the name of the test function, so
  without this nothing on disk connects a failure to the logs which might explain it. The window is
  how a failure is placed: rooms never overlap, so a room owns every moment from its own start to the
  next room's. Not to its own end — an error thrown out of a test is recorded after its room has been
  torn down, so a window closed at `endedAt` places exactly the failures worth placing nowhere.
- `clean-rooms/<user>/client-logs/` — the desktop client's own log for that test: the account and
  the domain lifecycle.
- `clean-rooms/<user>/extension-logs/` — the File Provider extension's log for that test, which is
  the only account of what the system asked the provider to do and what it answered. Debug level is
  switched on for every clean room, because the failures worth having it for are the ones nobody
  thought to enable it for beforehand. A domain's log outlives its test by no more than the next
  client start, so it is taken at teardown or not at all.
- `diagnostics/<user>/` — for a failing test: the client log, the server log, the File Provider
  defaults, the relevant part of the unified log, and the enumeration ledger.
- `metrics.md` — the propagation and materialization timings, which JUnit cannot express.
- `client-configuration-backup/` — the configuration which was on the machine before the run.

The enumeration ledger deserves a note. Enumerating a directory inside a domain is not a passive
observation: the first read of a container is what drives the extension's enumerator for it. The
harness therefore never walks a tree, records every directory a test did enumerate, and lists only
those in a diagnostics bundle — collecting diagnostics must not change the state being diagnosed.

## What the client does, and how the harness accommodates it

Headless account setup was broken in released client 34.0.3 in two ways: command-line setup was
refused whenever File Provider mode was on, and `--apppassword` was never persisted, so the account
could never authenticate. Both are fixed in
[nextcloud/desktop#10726](https://github.com/nextcloud/desktop/pull/10726); this suite was brought up
against a development build carrying that fix, with `--allow-development-client`.

Two behaviours of the fixed client shape the harness and are worth knowing before reading
``CleanRoom``:

1. **Account setup is a one-shot provisioning run.** The client starts, writes the account, and exits
   — without creating a File Provider domain, because the settings controller does not know the
   account yet and logs `Account not found for user …` at that point. An ordinary second launch turns
   the configured account into a domain. The clean room therefore launches twice, which is what
   `DesktopClient.provisionAccount(_:timeout:)` and the plain launch after it are for.
2. **Reading a domain can block in the kernel indefinitely.** An `open` or `readdir` under
   `~/Library/CloudStorage` waits for the provider to answer, and a provider which is starting, wedged
   or unauthenticated never does. Such a call is not cancellable, so every wait gives each attempt its
   own deadline and abandons it — see `Deadline` and `Waiter.attemptTimeout`. Without that, a wait
   never reaches its own timeout and the whole run hangs.

3. **Synchronisation can be blocked from outside the client.** Setting the `blockSync` boolean in the
   File Provider extension's own preferences stops it performing any network input or output: every
   request the system makes of it which would need the server is refused with
   `NSFileProviderErrorServerUnreachable`, in both directions. `ClientSynchronisation` writes it with
   the `defaults` tool, which reaches the extension's sandbox container where a `UserDefaults` suite
   opened from this process would not.

## When a test finds something

A failing test here is usually a client defect, and the step between noticing that and filing it
upstream is mostly transcription: which client, which server, which macOS, what was asserted, what
happened instead. That part is done for you.

A failed run drafts a report per defect into `Artifacts/<run>/reports/`, and `swift run tests report`
does the same on demand for any run — name it, or leave it out for the most recent one. The document
follows the bug template of [nextcloud/desktop](https://github.com/nextcloud/desktop) field by field,
so it is pasted rather than rewritten: what the defect is, how to reproduce it, what was expected,
what happened instead, which files were affected, the environment, and an excerpt of the File
Provider extension's own log around the failure.

One report covers one defect rather than one failure. Every test runs against every server in the
matrix, so a client defect arrives as four failures differing only in a port number and the room they
happened in — and four near-identical documents describing one problem are worse than one. Failures
are grouped by the test, the expectation within it and what that expectation said once the parts
which vary per run are elided. Two expectations failing, or one expectation failing for two different
reasons, stay two reports.

Grouping is also what makes the most useful line in a first report possible, because no single
failure knows it: *"Affected: `latest`, `latest+push`. Not affected: `33`, `33+push`."* A maintainer
reading that has a bisection already started.

The comparison is worth reading even when it is empty. A defect in the client is usually selective —
it tracks something the matrix varies, which is why the matrix exists. One which tracks nothing, and
fails identically on every server, is as often a fault in the suite doing the observing, so a report
in that shape carries a line saying to rule the suite out first. That is not a hunch: this project's
first sixteen failures were uniform across four servers and every one of them was a single broken
accessor in the harness. The shape said so before any of the messages did.

An existing report is never overwritten without `--force`, because the point of a draft is that
somebody edits it. A failure the suite already knows about is skipped: it is being watched on purpose
and is not news.

Every section is filled. There are no blanks to come back to and no headings standing over nothing,
because a document which is mostly a list of chores teaches its reader to skim.

The description is quoted rather than composed. An expectation in this suite carries a sentence
saying what must not happen — *"the version written on the server was replaced by the one written
locally, and nothing was kept of it"* — written by a person when the test was written. That sentence
is the description, and its first clause is the title, which makes writing a good comment beside an
expectation the same act as writing a good bug report.

What a run cannot establish is simply absent rather than stubbed. A suspected cause belongs to
whoever has read the client's source, and a guessed one in a generated document sends a maintainer
down a path for no reason.

The *Environment* section is worth more than it looks. Alongside the versions it carries every
preflight check the run made and a sentence on isolation — that tests run one at a time, and that the
account, its domain and its server user existed for this test alone. That forecloses the first
alternative explanation anybody reaches for. This project spent two runs eliminating its own harness
before any of it was written down.

**Nothing is filed for you.** The command drafts; you finish it and post it. That is not politeness:
the client's own contribution policy requires an issue to be in the contributor's words and forbids
an agent opening one.

Reports live under `Artifacts/`, which is git-ignored, and the writer refuses to run anywhere the
repository would pick it up. A draft describes a defect nobody has reported yet and this repository
is public, so that check is made rather than assumed.

Once an issue exists, wrap the detecting test so the suite goes green while the defect stays covered:

```swift
withKnownIssue("nextcloud/desktop#12345") {
    // the assertion which fails
}
```

Swift Testing then reports *expected issue did not occur* when the client is fixed, which is how a
fix upstream reaches this suite without anyone remembering to check.

## Making the two sides disagree

Some behaviour only appears when the client and the server hold different versions of the same file
at the same time, and arranging that is harder than it sounds: a client which is talking to its
server does not stay out of date long enough to be caught. There are two ways to produce it, and they
are not interchangeable.

| Tool | What it stops | Use it for |
| --- | --- | --- |
| `ServerWorkspace.withServerPaused` | the whole server, for everybody | outages: the client cannot reach the server, and neither can this suite |
| `ServerWorkspace.withSynchronisationBlocked` | the whole client, both directions | a client which is up but deaf, on any macOS the suite supports |
| `SyncControl.pause` / `resume` | one item | **conflicts** |

Suspending the container cannot produce a conflict, because the remote half of the disagreement has
to be created through the very server which is suspended.

Blocking the client can produce a divergence, but not a *conflict test*, and the difference cost this
project a wrong bug report. macOS asks a provider to detect a conflict only when an application asked
for that treatment: it pauses the item it has open and resumes with
`NSFileManagerResumeSyncBehaviorAfterUploadWithFailOnConflict`. Absent that, the documented behaviour
is `preserveLocalChanges` — the local version is uploaded and the server "may create a conflict copy,
or may automatically pick the winner". A test which merely arranges a divergence and waits is
measuring that default, and has no standing to call either permitted outcome a defect.

So the conflict suite goes through `SyncControl`, which takes the same route a document-based
application takes. It is per-item, addressed by URL, needs no provider identity and no change to the
client, and is the only way to ask for conflict detection at all. `SyncControl.supportedControls`
reads what the provider advertises through `NSURLUbiquitousItemSupportedSyncControlsKey`, because the
fail-on-conflict behaviour is only available where the provider says it is supported — a provider
which handles the error but never advertises the capability has written code no application may
reach. These calls are macOS 26 and newer.

A blocked client is dangerous in a way a suspended container is not. A frozen container announces
itself, because the next test cannot reach its server at all. A blocked client is silent: every later
test simply waits for something which is never going to happen. So the value is cleared on the way
out of the scope which set it, again when a clean room is built, and again by a full reset; a machine
left blocked is reported by `swift run tests doctor` and refused by preflight before a run starts.

## Troubleshooting

**A domain exists but cannot be read, or a dialog asks whether the application may access files
managed by Nextcloud.** Full Disk Access is missing for the application which started the run. Grant
it, restart that application, and check with `swift run tests doctor`. Reads block while such a dialog
is unanswered and are refused outright once macOS stops asking, so this looks by turns like a hang and
like a permission bug.

**A test finds demo content in a supposedly empty user.** The skeleton directory is switched off per
container after deployment. If a release ignores that, the user's root has to be emptied per user
instead — see spike S8 below.

**The client is running but no domain appears.** Check `attachments/`, then the client log in
`diagnostics/`. The clean room reads that log itself and fails immediately when the client reports
that it gave up on the account, rather than waiting for a domain which will never arrive.

**A domain directory outlives its test.** The client reaps domains without an account when it next
starts. Spike S7 establishes whether that holds up over hundreds of clean rooms.

**Open spikes.** These questions shape the design and are answered here as they are settled:

| # | Question | Status |
| --- | --- | --- |
| S1 | Do the account options really produce a domain, and how quickly? | **yes**, after a second launch, in about ten seconds |
| S2 | Is File Provider mode on by default, or does a setting have to be pre-seeded? | **on by default**: `macFileProviderModeEnabled=true` in `[General]` of `nextcloud.cfg`, written by the client itself when it starts without a configuration |
| S3 | Do `evictUbiquitousItem` and `startDownloadingUbiquitousItem` work on these items? | **yes, both** — a process outside the provider's application can evict a materialized item and can ask for one to be fetched without reading it |
| S4 | Does the Full Disk Access grant survive rebuilds of the test binary? | **yes** — the grant follows the application which starts the run, not the ad-hoc-signed test binary. It is also mandatory: see *Machine setup* |
| S5 | Is the client reset complete — does a second run start clean? | **yes** for the container state; the Keychain part is unproven, because the sandboxed client's items are not visible to the `security` tool |
| S6 | What is the baseline propagation latency, with and without push? | **measured both ways** — see *What has been measured* |
| S7 | Does the clean room hold up over hundreds of repetitions? | **holding** at roughly 116 rooms in one run across four servers, with no leaked user, domain or client process. Several hundred is still unproven |
| S8 | Does switching off the skeleton directory work on every supported release? | **yes** on both halves of the matrix, 34.0.3 and 33.0.8, verified by the server provisioning suite and again by the domain lifecycle one |

## License

See [LICENSE](LICENSE).

## Contributing

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) is expected to be installed and is
configured by [.swiftformat](.swiftformat). Before submitting a pull request, run it over the
repository:

```bash
swiftformat .
```
