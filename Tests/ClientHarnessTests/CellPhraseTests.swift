// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Testing

///
/// Tests for ``CellPhrase``.
///
/// The examples are real cell descriptions taken from the matrix, and they are pinned rather than eyeballed because the whole point of the sentence is to be read instead of the identifier. A phrase which silently drops an axis makes two different cells read identically, and a reader comparing two rows would have no way to tell.
///
@Suite("Cell phrase")
struct CellPhraseTests {
    @Test(arguments: [
        ("local delete item:dataless kind:folderEmpty at:standard:root trash:with",
         "Local deletion of a dataless empty folder in the domain root, with Nextcloud server trash enabled"),
        ("local delete item:materialized kind:file size:small at:standard:subdirectory trash:without",
         "Local deletion of a materialized small file in a subfolder, with Nextcloud server trash disabled"),
        ("remote create parent:dataless kind:bundle at:standard:subdirectory",
         "Remote creation of a bundle in a subfolder the client had never enumerated"),
        ("concurrent metadataUpdate item:materialized kind:folderWithChildren at:standard:root",
         "Concurrent rename of a materialized non-empty folder in the domain root"),
        ("remote contentUpdate item:dataless kind:file size:empty at:standard:root",
         "Remote content change of a dataless empty file in the domain root"),
        ("local move parents:materialized->dataless kind:file size:small from:standard:root to:standard:subdirectory",
         "Local move of a small file from the domain root into a subfolder the client had never enumerated"),
        ("remote move parents:dataless->materialized kind:folderWithChildren from:standard:subdirectory to:standard:root",
         "Remote move of a non-empty folder from a subfolder the client had never enumerated into the domain root"),
    ])
    func `Every axis of a cell reaches its sentence.`(_ example: (cell: String, expected: String)) {
        #expect(CellPhrase.sentence(for: example.cell) == example.expected)
    }

    @Test
    func `A suite name is still readable when there is no cell to phrase.`() {
        // Rooms recorded before the cell was written into the manifest, and the hand-written suites which have no cell at all.
        #expect(CellPhrase.sentence(for: "ConcurrentDelete.folderWithChildren.dataless") == "Concurrent delete folder with children dataless")
    }

    @Test
    func `A quadrant reads as words rather than as an identifier.`() {
        #expect(CellPhrase.heading(for: "concurrent contentUpdate") == "Concurrent Content Update")
        #expect(CellPhrase.heading(for: "ConcurrentContentUpdate") == "Concurrent Content Update")
    }

    ///
    /// Cells which differ in exactly one axis must not read the same.
    ///
    /// This is the failure the type's own documentation warns about, and it had happened twice over. The encoding was parsed and never printed, and a container's realization was dropped wherever the container was the domain root — together those made a hundred and ninety-four of the four hundred and sixty-one rows of the run of 2026-10-11 share a sentence with another row.
    ///
    /// Written as groups rather than as expected strings on purpose. What matters is that the members of a group differ, not what any of them says, and pinning the sentences would make this test fail for a rewording as readily as for a regression.
    ///
    @Test(arguments: [
        [
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:nfc",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:nfd",
            "remote metadataUpdate item:dataless kind:file size:small at:standard:root enc:caseCollision",
        ],
        [
            "remote create parent:materialized kind:bundle at:standard:root",
            "remote create parent:materializedDeep kind:bundle at:standard:root",
        ],
        [
            "local move parents:materialized->dataless kind:file size:small from:standard:root to:standard:subdirectory",
            "local move parents:materializedDeep->dataless kind:file size:small from:standard:root to:standard:subdirectory",
        ],
        [
            "remote delete item:materialized kind:folderWithChildren at:standard:subdirectory trash:with",
            "remote delete item:materializedDeep kind:folderWithChildren at:standard:subdirectory trash:with",
        ],
    ])
    func `Two cells differing in one axis do not read as one.`(_ group: [String]) {
        let sentences = group.map { CellPhrase.sentence(for: $0) }

        #expect(Set(sentences).count == group.count, """
        \(group.count) cells render as \(Set(sentences).count) sentences, so a reader comparing their rows cannot tell them apart: \(sentences.joined(separator: " / "))
        """)
    }

    @Test
    func `The domain root says when its contents were fetched and stays quiet otherwise.`() {
        // Saying that the root was enumerated is noise, because it always is. Saying that its children came down with it is not, and the model emits the two as separate cells.
        #expect(CellPhrase.sentence(for: "remote create parent:materialized kind:bundle at:standard:root") == "Remote creation of a bundle in the domain root")
        #expect(CellPhrase.sentence(for: "remote create parent:materializedDeep kind:bundle at:standard:root") == "Remote creation of a bundle in the domain root, with its contents fetched")
    }

    @Test
    func `A name which collides with a sibling by case says so.`() {
        #expect(CellPhrase.sentence(for: "remote move parents:materialized->dataless kind:bundle from:standard:root to:standard:subdirectory enc:caseCollision").hasSuffix("under a name a sibling already holds in another case"))
    }
}
