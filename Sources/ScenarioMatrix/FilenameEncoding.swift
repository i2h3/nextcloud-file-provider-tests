// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// How a filename is encoded on the wire versus on disk.
///
/// This is the one factor from a sibling project that changes the *correctness of an assertion* rather than merely timing: macOS stores decomposed (NFD) while the server stores what it was sent (typically precomposed, NFC), so "exactly one item per name" is not well defined until the comparison form is.
///
/// An asymmetric normalisation policy shows up as a duplicate-upload after a local enumeration, and only in the server→local direction — which is why this is gated on ``Origin/remote`` rather than applied everywhere.
///
/// The gate itself is ``Constraints/encodingValues(for:operation:available:)``, which narrows further to the operations that introduce or change a name and keeps a `nil` baseline alongside the variants, so the encoding cells add to the coverage of a quadrant rather than replacing it. The assertion the axis exists for is ``Oracle/noDuplicatesOrOrphans``: one item per name, no stray conflict copies.
///
public enum FilenameEncoding: String, CaseIterable, Hashable, Sendable {
    ///
    /// Precomposed. What a server typically stores.
    ///
    /// The form a name arrives in from the server, and therefore the form the client has to decide what to do with when it writes it to a volume which stores the other one.
    ///
    case nfc

    ///
    /// Decomposed. What macOS writes to disk.
    ///
    /// The form the local half of a comparison is in, which is why a comparison that does not normalise both sides reports two items where there is one.
    ///
    case nfd

    ///
    /// Differs only by case from an existing sibling — the documented trigger for a local-name bounce on a case-insensitive volume, observable through the `com.apple.fileprovider.before-bounce#PX` extended attribute.
    ///
    /// The one variant whose evidence is a thing to read rather than a thing to infer: the extended attribute records the name the item had before the system bounced it, so a cell using this value can say which name was rejected instead of only that two names ended up colliding.
    ///
    case caseCollision
}
