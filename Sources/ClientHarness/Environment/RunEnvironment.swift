// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Everything a test process needs to know about the run it is part of.
///
/// A run is described entirely by environment variables, so any single test can be reproduced by hand from the values recorded in its artifacts. The ``Runner`` sets them; the test target reads them through this type and through ``RequiresLiveEnvironmentTrait``, which skips the live suites when they are absent.
///
/// The path of the desktop client is deliberately not part of this: it is always ``ClientPaths/application``, because app extensions are only reliably loaded from `/Applications` and testing a copy elsewhere would not imitate a real deployment.
///
public struct RunEnvironment: Sendable {
    ///
    /// The name of the environment variable which controls whether destructive steps may run without asking.
    ///
    public static let allowDestructiveVariableName = "FPT_ALLOW_DESTRUCTIVE"

    ///
    /// The name of the environment variable which accepts a client the system policy would reject.
    ///
    /// The subject of these tests is normally the notarized build a user installs. A development build has to be testable too — that is how a fix is verified before it is released — but only when it is asked for, and the report says so.
    ///
    public static let allowUnnotarizedClientVariableName = "FPT_ALLOW_UNNOTARIZED_CLIENT"



    ///
    /// The name of the environment variable pointing at the directory collecting logs, attachments and reports.
    ///
    public static let artifactsDirectoryVariableName = "FPT_ARTIFACTS_DIR"

    ///
    /// The name of the environment variable carrying the JSON description of the servers under test.
    ///
    public static let matrixVariableName = "FPT_MATRIX"

    ///
    /// The name of the environment variable pointing at a file which holds that same JSON.
    ///
    /// The ``Runner`` passes the matrix inline, because it deploys the servers itself and knows it. Xcode cannot: the ports are assigned when the containers start, so the matrix is different every time, and an environment variable typed into a scheme would be stale before it was used twice. Pointing at a file instead makes the scheme setting permanent — `tests prepare` rewrites the file, and the scheme keeps working. The inline variable wins when both are set.
    ///
    public static let matrixFileVariableName = "FPT_MATRIX_FILE"

    ///
    /// The name of the environment variable scaling every timeout in the suite.
    ///
    public static let timeoutScaleVariableName = "FPT_TIMEOUT_SCALE"

    ///
    /// How many times a characterisation suite repeats each of its trials, or nothing to leave those suites switched off.
    ///
    /// Characterisation is a different activity from testing and is kept behind its own switch for that reason. A contract test asks whether the client did the right thing once; a characterisation suite asks how often it does, which means running the same thing dozens of times and reporting a rate rather than a verdict. Nobody wants the second on every run, and a rate measured from a single sample is worse than no rate at all.
    ///
    /// This exists because a defect turned out to be intermittent. Deletions of items whose content was never downloaded reached the server in some runs and not others, and two runs of twelve cells could say only that the failures were real and were confined to placeholders — not how often, and not what they depend on.
    ///
    public static let repetitionsVariableName = "FPT_REPETITIONS"

    ///
    /// The directory collecting logs, attachments and reports of this run.
    ///
    public let artifactsDirectory: URL

    ///
    /// Whether destructive steps may run without asking for confirmation first.
    ///
    /// This is what continuous integration and repeated local runs set. Without it the harness still runs, but it prints an inventory of what it is about to remove and waits for a confirmation on the terminal.
    ///
    public let isDestructiveAllowed: Bool

    ///
    /// Whether a client the system policy rejects is accepted as the subject.
    ///
    public let isUnnotarizedClientAllowed: Bool

    ///
    /// The servers this process is expected to test against, in the order the ``Runner`` deployed them.
    ///
    public let servers: [ServerUnderTest]

    ///
    /// The factor every timeout in the suite is multiplied with.
    ///
    /// A slow or loaded machine can raise it instead of every timeout being edited individually. Values which are not a positive number are rejected rather than silently ignored, because a mistyped scale would otherwise turn into confusing timeout failures much later.
    ///
    public let timeoutScale: Double

    ///
    /// Whether the given environment describes a live run at all.
    ///
    /// This is the cheap check ``RequiresLiveEnvironmentTrait`` uses to decide between running and skipping. It deliberately does not validate the contents: a present but broken matrix should fail loudly rather than be skipped silently.
    ///
    /// - Parameters:
    ///     - variables: The environment to inspect. Defaults to the environment of the current process.
    ///
    /// - Returns: `true` if the variables describing a live run are present.
    ///
    ///
    /// How many trials a characterisation suite should run, if any were asked for.
    ///
    /// - Parameters:
    ///     - variables: The environment to read. Defaults to this process's own.
    ///
    /// - Returns: The number of trials, or `nil` when none was asked for or the value does not name a positive count — in which case the characterisation suites stay switched off rather than guessing at a number.
    ///
    public static func repetitions(in variables: [String: String] = ProcessInfo.processInfo.environment) -> Int? {
        guard let raw = variables[repetitionsVariableName] else {
            return nil
        }

        guard let value = Int(raw) else {
            return nil
        }

        guard value > 0 else {
            return nil
        }

        return value
    }

    public static func isLive(_ variables: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let matrix = try? rawMatrix(from: variables) else {
            return false
        }

        return !matrix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    ///
    /// The JSON description of the servers under test, from whichever source carries it.
    ///
    /// - Parameters:
    ///     - variables: The environment to read.
    ///
    /// - Returns: The raw JSON.
    ///
    /// - Throws: A ``RunEnvironmentError`` if neither source is usable.
    ///
    private static func rawMatrix(from variables: [String: String]) throws -> String {
        if let inline = variables[matrixVariableName], !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inline
        }

        guard let path = variables[matrixFileVariableName], !path.isEmpty else {
            throw RunEnvironmentError.variableMissing(name: matrixVariableName)
        }

        guard let contents = try? String(contentsOf: URL(filePath: path), encoding: .utf8) else {
            throw RunEnvironmentError.matrixFileNotReadable(path: path)
        }

        return contents
    }

    ///
    /// Decode the environment of a run.
    ///
    /// - Parameters:
    ///     - variables: The environment to decode. Defaults to the environment of the current process.
    ///
    /// - Returns: The decoded description of the run.
    ///
    /// - Throws: A ``RunEnvironmentError`` if a required variable is missing or unusable.
    ///
    public static func decode(_ variables: [String: String] = ProcessInfo.processInfo.environment) throws -> RunEnvironment {
        let matrix = try rawMatrix(from: variables)

        let servers: [ServerUnderTest]

        do {
            servers = try JSONDecoder().decode([ServerUnderTest].self, from: Data(matrix.utf8))
        } catch {
            throw RunEnvironmentError.matrixNotDecodable(reason: String(describing: error))
        }

        guard !servers.isEmpty else {
            throw RunEnvironmentError.matrixEmpty
        }

        let artifactsDirectory = try resolvedArtifactsDirectory(from: variables)

        let timeoutScale: Double

        if let rawTimeoutScale = variables[timeoutScaleVariableName], !rawTimeoutScale.isEmpty {
            guard let parsed = Double(rawTimeoutScale), parsed > 0 else {
                throw RunEnvironmentError.variableNotDecodable(name: timeoutScaleVariableName, value: rawTimeoutScale)
            }

            timeoutScale = parsed
        } else {
            timeoutScale = 1
        }

        return RunEnvironment(
            artifactsDirectory: artifactsDirectory,
            isDestructiveAllowed: isTruthy(variables[allowDestructiveVariableName]),
            isUnnotarizedClientAllowed: isTruthy(variables[allowUnnotarizedClientVariableName]),
            servers: servers,
            timeoutScale: timeoutScale
        )
    }

    ///
    /// Where this run collects its artifacts.
    ///
    /// Named outright when the ``Runner`` starts the process. When the matrix comes from a file instead, the directory holding that file is used, so that a scheme in Xcode needs one setting rather than two which have to agree.
    ///
    /// - Parameters:
    ///     - variables: The environment to read.
    ///
    /// - Returns: The directory.
    ///
    /// - Throws: A ``RunEnvironmentError`` if neither source names one.
    ///
    private static func resolvedArtifactsDirectory(from variables: [String: String]) throws -> URL {
        if let named = variables[artifactsDirectoryVariableName], !named.isEmpty {
            return URL(filePath: named, directoryHint: .isDirectory)
        }

        guard let path = variables[matrixFileVariableName], !path.isEmpty else {
            throw RunEnvironmentError.variableMissing(name: artifactsDirectoryVariableName)
        }

        return URL(filePath: path, directoryHint: .notDirectory).deletingLastPathComponent()
    }

    ///
    /// Whether the environment already approves destructive steps, so that nothing has to be confirmed on the terminal.
    ///
    /// - Parameters:
    ///     - variables: The environment to read. Defaults to the environment of the current process.
    ///
    /// - Returns: `true` if destructive steps were approved up front.
    ///
    public static func isDestructiveAllowedByEnvironment(_ variables: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isTruthy(variables[allowDestructiveVariableName])
    }

    ///
    /// Interpret the common spellings of an affirmative environment variable value.
    ///
    /// - Parameters:
    ///     - value: The raw value, if the variable is set at all.
    ///
    /// - Returns: `true` if the value means yes.
    ///
    ///
    /// Whether an environment variable's value reads as an affirmative.
    ///
    /// Public because the test target asks the same question of the same variables, and two answers to "is this set" would eventually disagree about `1` against `true` against `yes`.
    ///
    public static func isTruthy(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return ["1", "true", "yes"].contains(value.lowercased())
    }

    ///
    /// Scale a duration by ``timeoutScale``.
    ///
    /// - Parameters:
    ///     - duration: The unscaled duration.
    ///
    /// - Returns: The duration to actually wait for on this machine.
    ///
    public func scaled(_ duration: Duration) -> Duration {
        duration * timeoutScale
    }

    ///
    /// Create a description of a run.
    ///
    /// - Parameters:
    ///     - artifactsDirectory: The directory collecting logs, attachments and reports.
    ///     - isDestructiveAllowed: Whether destructive steps may run without asking.
    ///     - isUnnotarizedClientAllowed: Whether a client the system policy rejects is accepted as the subject.
    ///     - servers: The servers this process is expected to test against.
    ///     - timeoutScale: The factor every timeout is multiplied with.
    ///
    public init(artifactsDirectory: URL, isDestructiveAllowed: Bool, isUnnotarizedClientAllowed: Bool = false, servers: [ServerUnderTest], timeoutScale: Double) {
        self.artifactsDirectory = artifactsDirectory
        self.isDestructiveAllowed = isDestructiveAllowed
        self.isUnnotarizedClientAllowed = isUnnotarizedClientAllowed
        self.servers = servers
        self.timeoutScale = timeoutScale
    }
}
