// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import ServerHarness
import Testing

///
/// Tests for ``ContentFactory``.
///
/// Fixture content has to be reproducible, because a mismatch between what was uploaded and what arrived is only diagnosable if the same seed always produces the same bytes.
///
@Suite("Content factory")
struct ContentFactoryTests {
    @Test(arguments: [0, 1, 1024, 65537])
    func `The same seed and size always produce the same content.`(_ size: Int) {
        #expect(ContentFactory.content(size: size, seed: 7) == ContentFactory.content(size: size, seed: 7))
    }

    @Test(arguments: [0, 1, 7, 8, 9, 1024, 65537])
    func `The requested size is produced exactly.`(_ size: Int) {
        #expect(ContentFactory.content(size: size, seed: 3).count == size)
    }

    @Test
    func `Different seeds produce different content.`() {
        #expect(ContentFactory.content(size: 4096, seed: 1) != ContentFactory.content(size: 4096, seed: 2))
    }

    @Test
    func `The fingerprint of empty content is the known digest of nothing.`() {
        #expect(ContentFactory.fingerprint(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test
    func `Equal content has equal fingerprints and different content does not.`() {
        let first = ContentFactory.content(size: 2048, seed: 11)
        let second = ContentFactory.content(size: 2048, seed: 12)

        #expect(ContentFactory.fingerprint(of: first) == ContentFactory.fingerprint(of: first))
        #expect(ContentFactory.fingerprint(of: first) != ContentFactory.fingerprint(of: second))
    }
}
