// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// The trait gating every suite which needs a deployed server and the desktop client.
///
/// `AGENTS.md` documents `swift test` as the way to run the tests of this package, and that has to stay true on a laptop, on a build machine and on a hosted continuous integration runner — none of which have Docker, a signed client installation or Full Disk Access. Suites carrying this trait therefore report themselves as skipped instead of failing there, while `swift run tests` sets the environment which enables them.
///
extension Trait where Self == ConditionTrait {
    ///
    /// Enable the suite only when the runner has described a live run.
    ///
    static var requiresLiveEnvironment: Self {
        .enabled(if: RunEnvironment.isLive(), "No live environment. Run the suite through `swift run tests`.")
    }
}
