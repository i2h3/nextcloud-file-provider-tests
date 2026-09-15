// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Verifies that this machine can run the live suites at all.
///
/// Every check here corresponds to a failure mode which is otherwise expensive to recognise: a client which is not the signed build, a process without Full Disk Access seeing an empty `CloudStorage`, a Docker daemon which is not running, a disk with no room for the fixtures. The report is printed by `swift run tests doctor` and evaluated again inside the test process before the first test runs.
///
public enum Preflight {
    ///
    /// The amount of free disk space a run is assumed to need.
    ///
    public static let requiredFreeSpace: Int64 = 10 * 1024 * 1024 * 1024

    ///
    /// Check everything which does not depend on a deployed server.
    ///
    /// - Parameters:
    ///     - allowingUnnotarizedClient: Whether a client the system policy rejects is accepted as the subject, which is how a development build is verified before it is released.
    ///
    /// - Returns: The report.
    ///
    public static func checkMachine(allowingUnnotarizedClient: Bool = false) async -> PreflightReport {
        var checks = [PreflightCheck]()
        checks.append(clientInstallation())
        await checks.append(clientSignature())
        await checks.append(clientNotarization(isAllowedToBeRejected: allowingUnnotarizedClient))
        checks.append(fullDiskAccess())
        checks.append(clientApplicationData())
        await checks.append(synchronisationNotBlocked())
        await checks.append(docker())
        checks.append(freeSpace())

        return PreflightReport(checks: checks)
    }

    ///
    /// Check that the client under test is installed where it has to be.
    ///
    /// - Returns: The outcome.
    ///
    private static func clientInstallation() -> PreflightCheck {
        let isInstalled: Bool

        do {
            isInstalled = try LocalDirectory.exists(ClientPaths.application)
        } catch {
            // The third outcome, and the one this check used to report as the second. "Nothing is installed there" and "this process was not allowed to look" send a reader to entirely different remedies, and a preflight whose whole purpose is to separate states must not merge two of them at its first question.
            return PreflightCheck(
                subject: "Desktop client",
                isSatisfied: false,
                detail: "\(error)",
                remedy: "Grant Full Disk Access to the application which starts the run and restart it. Until then this check cannot tell whether the client is installed."
            )
        }

        guard isInstalled else {
            return PreflightCheck(
                subject: "Desktop client",
                isSatisfied: false,
                detail: "Nothing is installed at \(ClientPaths.application.path(percentEncoded: false)).",
                remedy: "Install the signed build from its disk image into /Applications and launch it once by hand, so that its File Provider extension is registered. The location is fixed: app extensions are not reliably loaded from anywhere else."
            )
        }

        let version = DesktopClient.installedVersion() ?? "unknown version"

        return PreflightCheck(subject: "Desktop client", isSatisfied: true, detail: "\(version) at \(ClientPaths.application.path(percentEncoded: false))")
    }

    ///
    /// Check that the installed client still has an intact signature.
    ///
    /// - Returns: The outcome.
    ///
    private static func clientSignature() async -> PreflightCheck {
        let result = try? await ProcessRunner.run(URL(filePath: "/usr/bin/codesign"), arguments: ["--verify", "--strict", ClientPaths.application.path(percentEncoded: false)])

        guard let result, result.isSuccess else {
            return PreflightCheck(
                subject: "Code signature",
                isSatisfied: false,
                detail: result?.standardError ?? "codesign could not be run.",
                remedy: "Reinstall the client from its signed disk image. These tests exist to exercise a distribution build, so a modified or unsigned copy is not a valid subject."
            )
        }

        return PreflightCheck(subject: "Code signature", isSatisfied: true, detail: "valid and strict")
    }

    ///
    /// Check that the installed client is accepted by the system policy.
    ///
    /// - Parameters:
    ///     - isAllowedToBeRejected: Whether a rejected client is accepted anyway, which is how a development build is verified before it is released.
    ///
    /// - Returns: The outcome.
    ///
    private static func clientNotarization(isAllowedToBeRejected: Bool) async -> PreflightCheck {
        let result = try? await ProcessRunner.run(URL(filePath: "/usr/sbin/spctl"), arguments: ["-a", "-t", "exec", "-vv", ClientPaths.application.path(percentEncoded: false)])

        guard let result, result.isSuccess else {
            let detail = result?.standardError ?? "spctl could not be run."

            guard isAllowedToBeRejected else {
                return PreflightCheck(
                    subject: "System policy",
                    isSatisfied: false,
                    detail: detail,
                    remedy: "Install a notarized build, or accept this one explicitly with \(RunEnvironment.allowUnnotarizedClientVariableName)=1. What users install is what should normally be tested."
                )
            }

            return PreflightCheck(subject: "System policy", isSatisfied: true, detail: "REJECTED, accepted anyway because \(RunEnvironment.allowUnnotarizedClientVariableName) is set. This is not the build a user would install: \(detail.replacingOccurrences(of: "\n", with: " "))")
        }

        return PreflightCheck(subject: "System policy", isSatisfied: true, detail: result.standardError.isEmpty ? "accepted" : result.standardError)
    }

    ///
    /// Check that this process may read the state of the client under test.
    ///
    /// A question of its own since macOS 27, which guards the application data of a hardcoded list of applications with `kTCCServiceSystemPolicyAppDataDetailed` and names both `com.nextcloud.desktopclient` and its group container in that list. Until then Full Disk Access covered this and no check was needed. A refusal now arrives as an unreadable configuration and an empty log directory, which is indistinguishable from a client which has never run.
    ///
    /// Nothing being there is not a failure. A machine which has not run the client yet has no configuration to read, and this says so rather than demanding a grant for a file which does not exist.
    ///
    /// - Returns: The outcome.
    ///
    private static func clientApplicationData() -> PreflightCheck {
        let outcomes = PrivacyProbe.clientApplicationData.map { ($0, $0.inspect()) }

        let refused = outcomes.compactMap { probe, outcome -> String? in
            guard case let .refused(code) = outcome else { return nil }

            return "\(probe.subject) (\(String(cString: strerror(code))))"
        }

        guard refused.isEmpty else {
            return PreflightCheck(
                subject: "Client data",
                isSatisfied: false,
                detail: "Refused \(refused.joined(separator: ", ")). Since macOS 27 the data of this client is protected separately from Full Disk Access.",
                remedy: "Allow the application which starts the run to read data from other applications, in System Settings, Privacy & Security, and quit it completely afterwards. macOS asks for this once and remembers a refusal, after which everything below this point fails as though the client had never run."
            )
        }

        let readable = outcomes.filter { $0.1 == .readable }.map { $0.0.subject }

        guard readable.isEmpty else {
            return PreflightCheck(subject: "Client data", isSatisfied: true, detail: "readable: \(readable.joined(separator: ", "))")
        }

        return PreflightCheck(subject: "Client data", isSatisfied: true, detail: "nothing to read, because the client has written no state on this machine yet")
    }

    ///
    /// Check that this process has Full Disk Access.
    ///
    /// Whether it also lifts the consent macOS asks for before one application may read the files managed by another is the open question this check exists to make answerable: a run which is refused a domain should be able to rule this out first, rather than guessing.
    ///
    /// - Returns: The outcome.
    ///
    private static func fullDiskAccess() -> PreflightCheck {
        let outcomes = PrivacyProbe.fullDiskAccess.map { ($0, $0.inspect()) }

        guard outcomes.contains(where: { $0.1 == .readable }) else {
            let refused = outcomes.compactMap { probe, outcome -> String? in
                guard case let .refused(code) = outcome else { return nil }

                return "\(probe.subject) (\(String(cString: strerror(code))))"
            }

            guard refused.isEmpty else {
                return PreflightCheck(
                    subject: "Full Disk Access",
                    isSatisfied: false,
                    detail: "The process supervising this run does not have it. Refused \(refused.joined(separator: ", ")).",
                    remedy: "Grant Full Disk Access to the application which starts the run, which is usually the terminal, in System Settings, Privacy & Security, and quit it completely afterwards. A privacy grant only takes effect for a newly launched process, and closing its window does not end it."
                )
            }

            // Every probe is gone rather than refused, which answers nothing about any grant and is a fault here rather than on this machine. macOS 27 did precisely this by moving the per-user privacy database into a protected container, and the check went on to report a machine which had the grant as a machine which did not.
            return PreflightCheck(
                subject: "Full Disk Access",
                isSatisfied: false,
                detail: "Cannot be determined, because none of the locations this check reads are on this system: \(PrivacyProbe.fullDiskAccess.map(\.subject).joined(separator: ", ")).",
                remedy: "This is a fault in the test suite rather than on this machine. The probes in PrivacyProbe.fullDiskAccess name locations this version of macOS no longer has, and have to be replaced with ones it protects."
            )
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: ClientPaths.cloudStorage.path(percentEncoded: false))

            return PreflightCheck(subject: "Full Disk Access", isSatisfied: true, detail: "granted, and \(ClientPaths.cloudStorage.path(percentEncoded: false)) is readable")
        } catch {
            return PreflightCheck(
                subject: "Full Disk Access",
                isSatisfied: false,
                detail: "Granted, but \(ClientPaths.cloudStorage.path(percentEncoded: false)) still cannot be read: \(error.localizedDescription)",
                remedy: "This is unusual. Check that the directory exists and that nothing else has locked it down."
            )
        }
    }

    ///
    /// Check that the client is not left blocked from synchronising.
    ///
    /// A run which was interrupted while it had blocked the client leaves the value behind, and the next run would then watch every one of its tests time out with nothing to say why. Catching it here turns a whole wasted run into one sentence.
    ///
    /// - Returns: The outcome.
    ///
    private static func synchronisationNotBlocked() async -> PreflightCheck {
        guard await ClientSynchronisation.isBlocked() else {
            return PreflightCheck(subject: "Synchronisation", isSatisfied: true, detail: "not blocked")
        }

        return PreflightCheck(
            subject: "Synchronisation",
            isSatisfied: false,
            detail: "The desktop client is blocked from synchronising, probably left behind by an interrupted run.",
            remedy: "Run `swift run tests reset`, or remove the value by hand with `defaults delete \(ClientPaths.fileProviderExtensionBundleIdentifier) \(ClientSynchronisation.key)`."
        )
    }

    ///
    /// Check that a Docker daemon is reachable.
    ///
    /// This asks the `docker` tool, which is a proxy rather than the real question: the servers are deployed through `NextcloudContainerManager`, which talks to the Docker Engine socket and never runs the tool at all. The two can in principle disagree — a socket which answers on a machine with no tool installed, or the reverse. The tool is used anyway because this type deliberately has no dependency on the container manager, which is what keeps its own tests hermetic, and the manager exposes no public way to ask whether the engine is reachable. A deployment failure reports the truth clearly enough when the proxy is wrong.
    ///
    /// - Returns: The outcome.
    ///
    private static func docker() async -> PreflightCheck {
        for path in ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"] {
            // A path this process may not inspect is simply not a candidate; the next one is tried, and a failure to find any is reported by the check itself.
            guard (try? LocalDirectory.exists(URL(filePath: path))) == true else {
                continue
            }

            let result = try? await ProcessRunner.run(URL(filePath: path), arguments: ["version", "--format", "{{.Server.Version}}"])

            guard let result, result.isSuccess else {
                continue
            }

            return PreflightCheck(subject: "Docker", isSatisfied: true, detail: "server \(result.standardOutput)")
        }

        return PreflightCheck(
            subject: "Docker",
            isSatisfied: false,
            detail: "No reachable Docker daemon was found.",
            remedy: "Start Docker Desktop or OrbStack. The servers under test are deployed as containers on this machine."
        )
    }

    ///
    /// Check that there is room for the fixtures.
    ///
    /// - Returns: The outcome.
    ///
    private static func freeSpace() -> PreflightCheck {
        let values = try? ClientPaths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return PreflightCheck(subject: "Free disk space", isSatisfied: true, detail: "unknown, assuming sufficient")
        }

        let gigabytes = Double(available) / 1_073_741_824

        guard available >= requiredFreeSpace else {
            return PreflightCheck(
                subject: "Free disk space",
                isSatisfied: false,
                detail: String(format: "%.1f GB available", gigabytes),
                remedy: "Free up space. Container images, materialized fixtures and log archives together need more than this."
            )
        }

        return PreflightCheck(subject: "Free disk space", isSatisfied: true, detail: String(format: "%.1f GB available", gigabytes))
    }
}
