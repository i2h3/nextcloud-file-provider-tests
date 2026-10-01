// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

///
/// Tests for recognising the name a File Provider item was given when it could not keep the one it asked for.
///
/// Hermetic, and pinned because a run found the harness unable to see a bounce which had plainly happened. Four cells arranged a collision, the system renamed the arriving item to `travelling-Sibling 2.rtfd` beside `travelling-sibling.rtfd`, and none of them carried the `before-bounce` attribute this used to rely on entirely. Each spent three minutes waiting for a name which was never going to appear, then reported that the item had not reached the client — while it stood in the listing the failure itself printed.
///
/// The shape is inference, not evidence, and it is easy to make too generous. A pattern which matched a stranger's file would hand the wrong item to a cell and produce a finding about the client from a file the client never touched, which is worse than not finding anything.
///
@Suite("Bounce recognition")
struct BounceRecognitionTests {
    @Test
    func `A name with the number the system appends is recognised as the same item.`() {
        #expect(ScenarioWorld.isBounce(of: "travelling-Sibling.rtfd", named: "travelling-Sibling 2.rtfd"))
        #expect(ScenarioWorld.isBounce(of: "travelling-Sibling.bin", named: "travelling-Sibling 17.bin"))
    }

    ///
    /// A folder and a package have no extension to put the number before, so it goes on the end.
    ///
    @Test
    func `A name without an extension is recognised too.`() {
        #expect(ScenarioWorld.isBounce(of: "travelling-Sibling", named: "travelling-Sibling 2"))
    }

    ///
    /// The sibling it collided with is not the bounce of it. This is the pairing the axis creates, so mistaking one for the other would be the harness measuring the wrong file every time.
    ///
    @Test
    func `The sibling which caused the collision is not mistaken for the bounced item.`() {
        #expect(!ScenarioWorld.isBounce(of: "travelling-Sibling.rtfd", named: "travelling-sibling.rtfd"))
        #expect(!ScenarioWorld.isBounce(of: "travelling-Sibling.rtfd", named: "travelling-Sibling.rtfd"))
    }

    @Test
    func `A different file which merely starts the same way is not a bounce.`() {
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report 2 copy.bin"))
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report two.bin"))
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report .bin"))
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report2.bin"))
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "reporting 2.bin"))
    }

    ///
    /// The extension has to survive the rename, or it is a different kind of thing.
    ///
    @Test
    func `A bounce which changed the extension is not recognised.`() {
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report 2.rtfd"))
        #expect(!ScenarioWorld.isBounce(of: "report.bin", named: "report 2"))
    }

    ///
    /// The convention is written twice — once to recognise a name a listing produced, once to produce the names a caller which may not list has to ask for — and the two must stay the same convention.
    ///
    /// The failure this rules out is silent in exactly the way that matters. A generator which drifted from the recogniser would look for names the system never gives, find nothing, and report that an item is missing — which is the sentence ``MovePropagationRateTests`` is currently being used to decide the truth of.
    ///
    @Test(arguments: ["travelling-Sibling.rtfd", "trial-1.bin", "travelling-Sibling", "archive.tar.gz"])
    func `Every name the generator proposes is one the recogniser accepts.`(_ name: String) {
        let candidates = ScenarioWorld.bounceCandidates(of: name)

        #expect(candidates.count == 4, "The generator stopped proposing the four names the loss path asks for.")

        for candidate in candidates {
            #expect(ScenarioWorld.isBounce(of: name, named: candidate), """
            The generator proposed "\(candidate)" for "\(name)" and the recogniser rejects it, so the two have drifted apart.
            """)
        }
    }

    ///
    /// The name itself is not among them, because the caller asks for that one separately and a duplicate would report the same finding twice.
    ///
    @Test
    func `The generator proposes the numbers the system uses, and not the original name.`() {
        #expect(ScenarioWorld.bounceCandidates(of: "trial-1.bin") == ["trial-1 2.bin", "trial-1 3.bin", "trial-1 4.bin", "trial-1 5.bin"])
        #expect(ScenarioWorld.bounceCandidates(of: "box") == ["box 2", "box 3", "box 4", "box 5"])
    }
}
