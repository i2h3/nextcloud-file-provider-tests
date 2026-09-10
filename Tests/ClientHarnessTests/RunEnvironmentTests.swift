// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Foundation
import Testing

///
/// Tests for ``RunEnvironment``.
///
/// These are hermetic: they decode dictionaries instead of the process environment, so they run anywhere, which is what keeps a bare `swift test` meaningful on a machine without Docker and without the desktop client.
///
@Suite("Run environment")
struct RunEnvironmentTests {
    ///
    /// A matrix describing a single server, as the runner would write it.
    ///
    static let matrix = """
    [{"tag":"latest","serverAddress":"http://localhost:8080","containerIdentifier":"abc123","adminUser":"admin","adminPassword":"secret","isPushEnabled":false}]
    """

    ///
    /// The minimum set of variables which describes a live run.
    ///
    static let variables = [
        RunEnvironment.artifactsDirectoryVariableName: "/tmp/artifacts",
        RunEnvironment.matrixVariableName: matrix,
    ]

    @Test
    func `A complete environment decodes into its servers.`() throws {
        let environment = try RunEnvironment.decode(Self.variables)

        #expect(environment.servers.count == 1)
        #expect(environment.servers.first?.tag == "latest")
        #expect(environment.servers.first?.containerIdentifier == "abc123")
        #expect(environment.servers.first?.isPushEnabled == false)
        #expect(environment.artifactsDirectory.path(percentEncoded: false) == "/tmp/artifacts/")
    }

    @Test
    func `The timeout scale defaults to one and is applied to durations.`() throws {
        let unscaled = try RunEnvironment.decode(Self.variables)
        #expect(unscaled.timeoutScale == 1)
        #expect(unscaled.scaled(.seconds(10)) == .seconds(10))

        var variables = Self.variables
        variables[RunEnvironment.timeoutScaleVariableName] = "2.5"

        let scaled = try RunEnvironment.decode(variables)
        #expect(scaled.scaled(.seconds(10)) == .seconds(25))
    }

    @Test(arguments: ["0", "-1", "fast"])
    func `A timeout scale which is not a positive number is rejected.`(_ value: String) throws {
        var variables = Self.variables
        variables[RunEnvironment.timeoutScaleVariableName] = value

        #expect(throws: RunEnvironmentError.variableNotDecodable(name: RunEnvironment.timeoutScaleVariableName, value: value)) {
            try RunEnvironment.decode(variables)
        }
    }

    @Test
    func `A missing matrix is reported as a missing variable rather than an empty run.`() throws {
        var variables = Self.variables
        variables[RunEnvironment.matrixVariableName] = nil

        #expect(throws: RunEnvironmentError.variableMissing(name: RunEnvironment.matrixVariableName)) {
            try RunEnvironment.decode(variables)
        }
    }

    @Test
    func `A matrix without servers is rejected.`() throws {
        var variables = Self.variables
        variables[RunEnvironment.matrixVariableName] = "[]"

        #expect(throws: RunEnvironmentError.matrixEmpty) {
            try RunEnvironment.decode(variables)
        }
    }

    @Test
    func `A present but broken matrix fails loudly instead of being treated as no run.`() throws {
        var variables = Self.variables
        variables[RunEnvironment.matrixVariableName] = "{ this is not a server list }"

        #expect(RunEnvironment.isLive(variables))
        #expect(throws: RunEnvironmentError.self) {
            try RunEnvironment.decode(variables)
        }
    }

    @Test(arguments: [("1", true), ("true", true), ("YES", true), ("0", false), ("", false)])
    func `Destructive steps are only pre-approved by an affirmative value.`(_ value: String, _ expected: Bool) throws {
        var variables = Self.variables
        variables[RunEnvironment.allowDestructiveVariableName] = value

        #expect(try RunEnvironment.decode(variables).isDestructiveAllowed == expected)
    }

    @Test
    func `An environment without a matrix is not a live run.`() {
        #expect(RunEnvironment.isLive([:]) == false)
        #expect(RunEnvironment.isLive([RunEnvironment.matrixVariableName: "  "]) == false)
    }

    ///
    /// This is what an Xcode scheme relies on: one setting which stays correct while the ports behind it change every session.
    ///
    @Test
    func `A matrix read from a file describes the same run as one passed inline.`() throws {
        let file = try Self.writeMatrixFile()

        defer {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }

        let variables = [RunEnvironment.matrixFileVariableName: file.path(percentEncoded: false)]

        #expect(RunEnvironment.isLive(variables))

        let environment = try RunEnvironment.decode(variables)
        #expect(environment.servers.count == 1)
        #expect(environment.servers.first?.tag == "latest")
    }

    ///
    /// Without this the scheme would need two settings which have to agree, and one of them would eventually not.
    ///
    @Test
    func `A matrix file names the artifacts directory when nothing else does.`() throws {
        let file = try Self.writeMatrixFile()

        defer {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }

        let environment = try RunEnvironment.decode([RunEnvironment.matrixFileVariableName: file.path(percentEncoded: false)])

        #expect(environment.artifactsDirectory.standardizedFileURL == file.deletingLastPathComponent().standardizedFileURL)
    }

    @Test
    func `An inline matrix wins over a file.`() throws {
        let file = try Self.writeMatrixFile(contents: "[]")

        defer {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }

        var variables = Self.variables
        variables[RunEnvironment.matrixFileVariableName] = file.path(percentEncoded: false)

        #expect(try RunEnvironment.decode(variables).servers.count == 1)
    }

    @Test
    func `A matrix file which cannot be read is reported as such.`() {
        let variables = [RunEnvironment.matrixFileVariableName: "/nowhere/matrix.json"]

        #expect(RunEnvironment.isLive(variables) == false)
        #expect(throws: RunEnvironmentError.matrixFileNotReadable(path: "/nowhere/matrix.json")) {
            try RunEnvironment.decode(variables)
        }
    }

    ///
    /// Write a matrix to a file of its own directory.
    ///
    /// - Parameters:
    ///     - contents: What to write. Defaults to ``matrix``.
    ///
    /// - Returns: The file.
    ///
    /// - Throws: Whatever creating the directory or writing raises.
    ///
    private static func writeMatrixFile(contents: String = matrix) throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appending(path: "matrix.json", directoryHint: .notDirectory)
        try Data(contents.utf8).write(to: file, options: .atomic)

        return file
    }
}
