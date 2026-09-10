// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Deploys the servers one run is to be tested against.
///
/// The list is derived rather than configured, for the reason ``ServerTags`` explains: the matrix is the current release and the one before it, and which two those are is a question only a running server can answer. So `latest` goes up first, reports its version, and decides what the second half of the matrix is.
///
/// This is shared by the two commands which deploy — the one that runs the tests itself and the one that prepares a session for Xcode — because the ordering rule is easy to get subtly wrong and there should be one copy of it.
///
public enum ServerMatrix {
    ///
    /// Deploy the servers of a run.
    ///
    /// Deployment is ordered newest first, which is not a preference but a requirement: the older half of a derived matrix is not known until the newer half has said what it is.
    ///
    /// - Parameters:
    ///     - tags: The releases to deploy, or an empty array to derive the matrix from what `latest` turns out to be.
    ///     - includesPush: Whether every release is additionally deployed with the High Performance Backend for Files.
    ///     - report: Called with each line worth showing while the deployment proceeds.
    ///
    /// - Returns: The deployed servers, in the order the tests will see them.
    ///
    /// - Throws: Whatever deployment raises, after deleting whatever had already been deployed.
    ///
    public static func deploy(tags: [String], includesPush: Bool, report: (String) -> Void) async throws -> [ManagedServer] {
        var deployed = [ManagedServer]()

        do {
            for tag in tags.isEmpty ? [ServerTags.latest] : tags {
                deployed += try await deploy(tag: tag, includesPush: includesPush, report: report)
            }

            guard tags.isEmpty else {
                return deployed
            }

            guard let versionString = deployed.first?.versionString else {
                throw ServerMatrixError.versionNotReported
            }

            guard let previous = ServerTags.previousMajor(before: versionString) else {
                throw ServerMatrixError.previousMajorNotDerivable(versionString: versionString)
            }

            report("Nextcloud \(ServerTags.latest) reports \(versionString), so the release before it is \(previous).")
            deployed += try await deploy(tag: previous, includesPush: includesPush, report: report)

            return deployed
        } catch {
            // Nothing else will ever hear about these containers, so they are removed here rather than left to be found by hand.
            for server in deployed {
                try? await server.delete()
            }

            throw error
        }
    }

    ///
    /// Deploy one release, once plainly and once with push notifications when asked.
    ///
    /// - Parameters:
    ///     - tag: The release to deploy.
    ///     - includesPush: Whether to deploy it a second time with the High Performance Backend for Files.
    ///     - report: Called with each line worth showing.
    ///
    /// - Returns: The deployed servers.
    ///
    /// - Throws: Whatever deployment raises.
    ///
    private static func deploy(tag: String, includesPush: Bool, report: (String) -> Void) async throws -> [ManagedServer] {
        var deployed = [ManagedServer]()

        for isPushEnabled in includesPush ? [false, true] : [false] {
            report("Deploying Nextcloud \(tag)\(isPushEnabled ? " with push notifications" : "")...")
            let server = try await ManagedServer.deploy(tag: tag, isPushEnabled: isPushEnabled)
            deployed.append(server)
            report("  \(server.versionString) reachable at \(server.descriptor.serverAddress.absoluteString)")
        }

        return deployed
    }
}
