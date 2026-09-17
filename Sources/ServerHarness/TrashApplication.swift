// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import NextcloudContainerManager

///
/// Turns a server's trash bin on and off.
///
/// `files_trashbin` is an application like any other on a Nextcloud server, and an administrator may disable it. That is not an exotic configuration: it is the case the client's own File Provider extension branches on, reading `capabilities.files.undelete` rather than assuming a trash exists, and it is a whole axis of the scenario matrix — sixty cells which could not be run because nothing here could produce a server in that state.
///
/// Toggled per room rather than deployed as a second server profile. The suites are serialized and a room holds the server to itself, so the state can be established for the cell being run and restored afterwards, which is one `occ` invocation against a running container rather than a second container for every release under test.
///
public enum TrashApplication {
    ///
    /// The application which provides the trash bin.
    ///
    public static let identifier = "files_trashbin"

    ///
    /// Turn the trash bin on or off.
    ///
    /// - Parameters:
    ///     - isEnabled: Whether deleted items should be kept.
    ///     - containerIdentifier: The container to change.
    ///
    /// - Throws: Whatever running the command raises.
    ///
    public static func setEnabled(_ isEnabled: Bool, inContainer containerIdentifier: String) async throws {
        try await NextcloudContainerManager.runOCC([isEnabled ? "app:enable" : "app:disable", identifier], inContainer: containerIdentifier)
    }
}
