// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A file name which one of the two sides spells differently from the other, carried together with what makes it awkward.
///
/// ``NamingTests`` is parameterized over a list of these, and the list is the whole content of that suite: each entry is a way two systems can disagree about what a name is. The type exists because the name on its own is a poor argument to be identified by. Four of the five are hard to tell apart in a terminal — one is precomposed and one decomposed, which look identical — one is long enough to fill a line, and one is an emoji with a variation selector.
///
/// So each carries a ``label`` as well, and that label is what reaches ``CleanRoom`` as part of the test name, which in turn is what names the Nextcloud user, the clean room directory and the row on the run's page. Before it existed, five rooms were called `Naming.fromServer` and a reader had no way at all to tell which name any of them had been about.
///
/// It is ``CustomStringConvertible`` for the same reason: Swift Testing prints an argument's description in the case's display name, and a raw spelling difference is invisible there.
///
struct AwkwardName: CustomStringConvertible, Sendable {
    ///
    /// A short, stable word naming the difficulty rather than the name.
    ///
    /// Lower case ASCII, because ``TestUserName/derive(from:ordinal:)`` replaces anything else with a hyphen, and short, because the derived user name is truncated to fit what `occ user:add` accepts.
    ///
    let label: String

    ///
    /// The name itself, exactly as it should be written or uploaded.
    ///
    let value: String

    ///
    /// Why this name is in the list, as a sentence a reader can act on.
    ///
    /// Shown in the test case's display name, so a failing case says what it was testing without anybody opening the suite.
    ///
    let why: String

    ///
    /// What Swift Testing prints for this argument.
    ///
    var description: String {
        "\(label) — \(why)"
    }
}
