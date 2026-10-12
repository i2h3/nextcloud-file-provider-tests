// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ScenarioMatrix
import Testing

///
/// Cells whose subject does not do what the model asks of it, and is not pretending to.
///
/// A cell can fail for three quite different reasons, and only one of them is a defect. It can find a bug; it can be beyond what this harness knows how to establish, which ``ScenarioSelection`` excludes and counts; or the client can be declining the feature outright, deliberately and on the record. That third case has no home in the model — ``ScenarioMatrix/Outcome/rejection`` describes a write refused by a container's permissions, not a capability the client has not shipped.
///
/// **These cells are run rather than excluded**, and that is the whole point of this type. A cell dropped from a run is coverage that disappears silently: the day the feature lands, nothing says the cells exist, nobody remembers to switch them back on, and the feature ships untested. So the cell runs, its failure is registered as expected, and Swift Testing does the remembering — when the client starts doing what the cell asks, `withKnownIssue` reports **expected issue did not occur** and the run fails until somebody removes the entry here.
///
/// That inversion is the design. Coverage cannot be lost by forgetting; it can only be lost by editing this file, which is a deliberate act with a reason attached.
///
enum KnownLimitation {
    ///
    /// Why this cell is expected to fail, if it is.
    ///
    /// - Parameters:
    ///     - cell: The cell's description.
    ///
    /// - Returns: The reason, or `nil` where the cell is expected to hold.
    ///
    static func reason(for cell: String) -> Comment? {
        guard cell.contains("kind:bundle") else {
            return nil
        }

        // What is refused is the client **uploading** a package, and nothing else. A package created on the server arrives in the client normally — five cells said so by failing this expectation rather than the cell — and deleting one the client never downloaded reaches the server like any other deletion.
        //
        // Narrowed twice, each time by a run contradicting it. The log line — "Refusing to sync bundle or package" — reads as though it covers everything, and each narrowing came from cells which were run rather than excluded. That is the argument for running them, made twice by the suite itself.
        //
        // Then widened once, by the same method and against the same client, for the one server-side operation two runs agree the client cannot perform on a package it has downloaded: deleting it. That carve-back is deliberately the narrowest the evidence supports. The other two server-side operations are measured in the message below and are **not** painted, because one of them works and the other one disagrees with itself between runs.
        let isDeletionOfMaterializedPackage = cell.contains(" delete ") && cell.contains("item:materialized")

        guard !cell.hasPrefix("remote ") || isDeletionOfMaterializedPackage else {
            return nil
        }

        guard !(cell.contains(" delete ") && cell.contains("item:dataless")) else {
            return nil
        }

        // Narrowed a third time, and again by cells which ran rather than by reasoning. A delete or a rename made on **both** sides at once does not fail, because the client's refusal is not what decides the outcome: the server's half of the operation carries it, and the contract — gone from both, or surviving under one of the permitted names — is satisfied regardless of what the client did with its own half.
        //
        // Measured twice, on 2026-10-09 and again on 2026-10-11, identically both times. The four concurrent-delete rooms log the refusal exactly twice each, so the client really does decline the deletion and the item goes anyway. The four concurrent-rename rooms log no refusal at all.
        //
        // Worth holding beside the carve-back above, because the two look contradictory and are not: the server deleting a materialized package on its own is not carried to the client, while the same deletion made on both sides at once converges. Whatever stalls the one-sided case, a simultaneous local change is enough to get past it.
        //
        // A concurrent *content* update is not carved out and must not be. Those two cells do fail, and are painted correctly — writing bytes into a package is the upload this client refuses, and no second side is doing it for them.
        guard !(cell.hasPrefix("concurrent ") && (cell.contains(" delete ") || cell.contains(" metadataUpdate "))) else {
            return nil
        }

        return """
        The client does not upload packages, deliberately. Its extension says so in its own log — "Refusing to sync bundle or package because this is not supported" — then adds the name to an ignore list and reports the exclusion to the main app over XPC. Measured on 2026-09-17 and 2026-09-18: a package created in the client never reaches the server, a rename of one never leaves the Mac, and deleting one the client has downloaded is dropped. What does work, and is therefore not expected to fail here: a package created on the server arriving in the client, and deleting one the client never downloaded.

        The refusal has a second effect which is not obvious from the log line and costs more than the refusal itself. Materializing a package is enough to trigger it: the system asks the extension to modify the item, the extension declines with `NSFileProviderErrorExcludedFromSync` (-2010) and reports the package to the main app as excluded. From then on the server can no longer delete it. Four rooms established a materialized package and deleted it on the server; in all four the deletion never reached the client within three minutes and the extension logged nothing about a deletion at all. The four rooms whose package stayed dataless propagated their deletion normally, which is the control. Measured on 2026-10-09 and again on 2026-10-11, eight failures out of eight, against the same client both times — which is why these four cells are painted and the other server-side operations are not.

        So a user who opens a synced package has, from that moment, a local copy the server can no longer delete.

        The other two server-side operations were measured in both of those runs and neither is painted, for opposite reasons. A **content** change into a materialized package is carried at a subdirectory and is not carried at the domain root; both runs said so, the same way round each time, so the cell at the root fails on every run and is left failing rather than painted, because a rule which has to name one placement and not the other encodes a distinction nothing here can explain. A **rename** of a materialized package arrived in both rooms on 2026-10-09 and in neither room on 2026-10-11, same client and same suite code, so it is intermittent in the plainest sense and is left to fail when it fails. An earlier version of this entry read the 2026-10-09 passes as working, with the caveat that each took a tenth of a second and so might have been this harness reading through its own lookup; the caveat was right to be there and the reading was wrong.

        Disabled by https://github.com/nextcloud/desktop/pull/9971; restoring it is tracked by https://github.com/nextcloud/desktop/issues/9827. When it lands, these cells stop failing and this expectation becomes the thing that fails — which is how the suite tells somebody to delete this entry rather than leaving the painted cells quietly untested. Their number is measured and pinned by ``ScenarioSelectionTests``, not carried in this sentence, because it was carried here as ninety-three for long enough to be wrong by nearly double.
        """
    }
}
