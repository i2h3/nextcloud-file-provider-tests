// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation

///
/// The place where a prepared session records what it left running.
///
/// A run started by ``Run`` needs none of this: it deploys the servers, hands them to the test process in an environment variable and deletes them afterwards, all within one process. A session prepared for Xcode outlives the process which created it, so what it left behind has to be written down — otherwise the containers are only findable by guessing at Docker, and the matrix cannot reach the test process at all.
///
/// The path is deliberately fixed rather than timestamped. It is typed into an Xcode scheme once, and a path which changed per session would defeat the point.
///
struct SessionDirectory {
    ///
    /// The directory the session is described in.
    ///
    let directory: URL

    ///
    /// The file holding the JSON description of the servers under test.
    ///
    var matrixFile: URL {
        directory.appending(path: "matrix.json", directoryHint: .notDirectory)
    }

    ///
    /// Describe the session directory beneath an artifacts directory.
    ///
    /// - Parameters:
    ///     - artifacts: The artifacts directory of the package.
    ///
    init(artifacts: String) {
        directory = URL(filePath: artifacts, directoryHint: .isDirectory)
            .appending(path: "session", directoryHint: .isDirectory)
            .absoluteURL
    }

    ///
    /// Record the servers of a session.
    ///
    /// - Parameters:
    ///     - servers: The deployed servers.
    ///
    /// - Throws: Whatever creating the directory or writing the file raises.
    ///
    func write(_ servers: [ServerUnderTest]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(servers).write(to: matrixFile, options: .atomic)
    }

    ///
    /// The servers a previous session left running, if there was one.
    ///
    /// - Returns: The servers, or an empty array when no session is recorded.
    ///
    func read() -> [ServerUnderTest] {
        guard let data = try? Data(contentsOf: matrixFile) else {
            return []
        }

        return (try? JSONDecoder().decode([ServerUnderTest].self, from: data)) ?? []
    }

    ///
    /// Forget the recorded session.
    ///
    func clear() {
        try? FileManager.default.removeItem(at: matrixFile)
    }
}
