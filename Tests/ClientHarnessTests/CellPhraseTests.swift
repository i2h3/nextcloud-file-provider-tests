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
}
