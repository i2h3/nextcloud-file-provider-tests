// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

extension String {
    ///
    /// The string with its first character upper-cased and everything after it left exactly as it was.
    ///
    /// The one caller is ``Quadrant/name``, which joins the raw values of ``Origin`` and ``Operation`` into a single camel-cased identifier such as `RemoteMetadataUpdate`.
    ///
    /// The standard library's `capitalized` cannot be used for that, and the difference is not cosmetic: it upper-cases the first letter of each word and lower-cases the remainder, so `metadataUpdate` becomes `Metadataupdate` and the camel case which makes the name readable — and which makes it line up with the name of the suite that runs the quadrant — is destroyed. Upper-casing exactly one character and appending the rest untouched is the whole point of this helper.
    ///
    /// It stays internal rather than becoming `private`, because its caller lives in another file and `private` is file-scoped. It is deliberately not `public`: it is a spelling detail of one computed property, not part of the vocabulary this model offers its users.
    ///
    var capitalizedFirst: String {
        guard let first else {
            return self
        }

        return first.uppercased() + dropFirst()
    }
}
