// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// How one launch of the desktop client is configured.
///
/// This is a typed model of the client's command line options, so that the exact invocation a test used can be recorded in its artifacts and repeated by hand. The options themselves were read from the help text of the installed build; ``arguments`` is the only place which knows their spelling.
///
/// There is deliberately no configuration or log directory here. The client is App Sandboxed, so it cannot write to a directory of our choosing: passing `--confdir` outside its container leaves it running with nothing configured and no explanation. A clean room therefore empties the client's own configuration directory — ``ClientPaths/configurationDirectory`` — instead of giving it a private one.
///
public struct ClientLaunchConfiguration: Hashable, Sendable {
    ///
    /// The account to create on startup, if this launch is supposed to configure one.
    ///
    /// A launch without an account is how a reset gets the client to reap the File Provider domains which no longer belong to anything.
    ///
    public let account: ClientAccount?

    ///
    /// Whether the account is created with virtual files enabled.
    ///
    /// On macOS the File Provider is selected by `macFileProviderModeEnabled` in the client's own configuration rather than by this option, which is why ``ClientReset`` makes sure that flag is set. The option is still passed, so that an account created here matches one created by a person who chose virtual files.
    ///
    public let isVirtualFilesEnabled: Bool

    ///
    /// The command line options equivalent to this configuration.
    ///
    /// Debug logging and flushing are always on: a log which is missing its last lines because they were still buffered when the extension was killed is worthless for diagnosing a failure.
    ///
    public var arguments: [String] {
        var arguments = [
            "--logdebug",
            "--logflush",
            "--background",
        ]

        guard let account else {
            return arguments
        }

        arguments += [
            "--serverurl", account.serverAddress.absoluteString,
            "--userid", account.userIdentifier,
            "--apppassword", account.appPassword,
            "--isvfsenabled", isVirtualFilesEnabled ? "1" : "0",
        ]

        return arguments
    }

    ///
    /// Create a launch configuration.
    ///
    /// - Parameters:
    ///     - account: The account to create on startup, if any.
    ///     - isVirtualFilesEnabled: Whether the account uses virtual files. Defaults to `true`, because the File Provider is what these tests are about.
    ///
    public init(account: ClientAccount? = nil, isVirtualFilesEnabled: Bool = true) {
        self.account = account
        self.isVirtualFilesEnabled = isVirtualFilesEnabled
    }
}
