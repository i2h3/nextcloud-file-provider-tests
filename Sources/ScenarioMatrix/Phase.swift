// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Which axis values the harness can actually establish today.
///
/// Coverage is full-minus-impossible, but "full" is only meaningful over axes the harness can drive. Several values have no setup path yet — not because they are uninteresting, but because the server-side library lacks the API. Encoding that as a phase keeps the generated matrix honest: it never claims a cell it cannot build.
///
/// This is the one axis of the model which describes the harness rather than the system under test, and it is the only argument ``Generator/matrix(for:)`` and ``Generator/scenarios(for:phase:)`` take besides the quadrant. The generator reads nothing but the properties below, so a value withheld here is as absent from the generated matrix as one ``Constraints`` rejects outright. The difference between the two is intent, and keeping it visible is the point: ``Constraints`` prunes what cannot happen, a phase prunes what cannot yet be built, and only the second of those is expected to shrink over time.
///
public enum Phase: String, CaseIterable, Hashable, Sendable {
    ///
    /// Everything drivable with no upstream work. Standard containers only.
    ///
    /// Every ``Placement`` of this phase therefore carries ``ContainerProfile/standard``, which is read-write by construction, so no cell of phase A expects an ``Outcome/rejection``: the refusal cells arrive with ``b``, together with the containers that can refuse.
    ///
    case a

    ///
    /// Adds shared and group-folder containers, read-only permissions, chunked uploads and the version oracle.
    ///
    /// Blocked on Rainmaker gaining the OCS Sharing, OCS Provisioning, groupfolders, versions and chunked-upload APIs.
    ///
    /// The chunked uploads named in that list have since shipped, which is why ``fileSizes`` offers ``FileSize/large`` from ``a`` onwards rather than waiting for this phase; the remaining blockers are the sharing, provisioning, groupfolders and versions APIs. What this phase still gates is ``ContainerType/shared``, ``ContainerType/groupfolder`` and ``Permission/readOnly``, and with them every cell whose expectation is a refusal.
    ///
    case b

    ///
    /// Adds a *driven* content policy.
    ///
    /// Blocked on a client change, because `contentPolicy` is read-only to a test process — the pin can be observed but not set.
    ///
    /// Until that changes ``contentPolicies`` offers ``ContentPolicy/default`` alone, and the ``Oracle/contentPolicyInheritance`` clause every cell carries asserts that the *default* resolution up the ancestor chain is correct rather than the resolution of a pin a test placed.
    ///
    case c

    ///
    /// Phases up to and including this one.
    ///
    /// Every axis property below asks this rather than comparing raw values, so a phase inherits everything its predecessors made drivable and a new phase only has to state what it adds.
    ///
    public var cumulative: [Phase] {
        switch self {
            case .a: [.a]
            case .b: [.a, .b]
            case .c: [.a, .b, .c]
        }
    }

    // MARK: - Axis availability

    ///
    /// The containers an item can be placed in.
    ///
    /// ``ContainerProfile/standard`` is available in every phase; the shared and group-folder types arrive at ``b`` in both permissions, which is what first makes ``ContainerProfile/rejectsWrites`` true for some cells and so what gives the matrix its expected rejections at all.
    ///
    /// ``Generator`` crosses these with ``locations`` to form every ``Placement`` a cell can sit in, and for a `move` every legal pair of them.
    ///
    public var containers: [ContainerProfile] {
        var profiles: [ContainerProfile] = [.standard]

        guard cumulative.contains(.b) else {
            return profiles
        }

        for type in [ContainerType.shared, .groupfolder] {
            for permission in [Permission.readWrite, .readOnly] {
                if let profile = ContainerProfile(type: type, permission: permission) {
                    profiles.append(profile)
                }
            }
        }

        return profiles
    }

    ///
    /// The file sizes worth writing, which is every one of them in every phase.
    ///
    /// `large` needs Nextcloud's chunked-upload protocol. This was a Phase B blocker until Rainmaker 4.0.0 (commit 6219dd7, "Close #69: Chunked uploads") shipped it: `upload(_:to:force:chunkSize:)` now stages through /remote.php/dav/uploads/<user> above a 5 MiB floor, defaulting to 10 MiB. Available from Phase A.
    ///
    /// ``Constraints/sizes(for:operation:available:)`` is what narrows this per cell, because a size only selects an upload path and so only matters where bytes are actually written.
    ///
    public var fileSizes: [FileSize] {
        FileSize.allCases
    }

    ///
    /// The pin states a cell can be built in.
    ///
    /// Phase A still asserts the content-policy oracle; it just asserts that the *default* resolution is correct, since a pin cannot be established.
    ///
    /// That is why the axis collapses to ``ContentPolicy/default`` before ``c`` rather than dropping the ``Oracle/contentPolicyInheritance`` clause: assuming the default resolution is correct is how inheritance bugs survive, so the oracle runs either way and only the values it runs over change.
    ///
    public var contentPolicies: [ContentPolicy] {
        cumulative.contains(.c) ? ContentPolicy.allCases : [.default]
    }

    ///
    /// Encoding is drivable from Phase A: it needs only the ability to create a remote item with a chosen name, which the server-side library already supports.
    ///
    /// Availability is not the same as breadth here. ``Constraints/encodingValues(for:operation:available:)`` hands these out only where a name arrives from the server, and ``Generator`` then collapses what is left to one representative per operation and kind, so a full axis at this end still produces a handful of cells.
    ///
    public var filenameEncodings: [FilenameEncoding] {
        FilenameEncoding.allCases
    }

    ///
    /// Whether the server under test keeps deleted items, which is drivable from Phase A in both directions.
    ///
    /// Nothing is needed of an API for this: ``TrashSupport`` is realised as two server profiles, established when the container is deployed and verified by reading the capability back. ``Constraints/trashValues(for:available:)`` restricts the axis to ``Operation/delete``, where the chosen value also decides the ``Contract`` the ``Oracle/trashPlacement`` clause is held to.
    ///
    public var trashSupport: [TrashSupport] {
        [.with, .without]
    }

    ///
    /// Where a change can come from, which is everywhere in every phase.
    ///
    /// Together with ``operations`` this is what ``Generator/matrix(for:)`` filters ``Quadrant/allCases`` against, so the suite spine is complete from ``a`` onwards; what varies between phases is how many cells each quadrant holds, never which quadrants exist.
    ///
    public var origins: [Origin] {
        Origin.allCases
    }

    ///
    /// What can be done to an item, which is everything in every phase.
    ///
    /// The counterpart of ``origins`` in the quadrant filter of ``Generator/matrix(for:)``.
    ///
    public var operations: [Operation] {
        Operation.allCases
    }

    ///
    /// What sort of thing the item under test can be, which is every kind in every phase.
    ///
    /// The outermost loop of ``Generator/scenarios(for:phase:)`` walks these, and ``Constraints/isLegal(operation:kind:)`` is what drops a kind an operation has nothing to act on.
    ///
    public var itemKinds: [ItemKind] {
        ItemKind.allCases
    }

    ///
    /// How deep within the domain an item can sit, which is every depth in every phase.
    ///
    /// Crossed with ``containers`` to form the ``Placement`` values of a cell. The depth is load-bearing beyond mere variety: ``Constraints/isLegal(contentPolicy:site:)`` needs ``Location/subdirectory`` for an inherited pin to be observable at all, and ``Constraints/isLegal(containerRealization:location:)`` fixes the root's own realization because the domain root is enumerated as soon as the domain mounts.
    ///
    public var locations: [Location] {
        Location.allCases
    }
}
