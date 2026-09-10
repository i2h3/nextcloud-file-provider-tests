// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation

///
/// Asks on the terminal before something irreversible happens.
///
/// The suite is meant to be written and debugged on an ordinary developer machine, where the client may hold an account somebody cares about. The guard is therefore an informed question rather than a refusal to run: what was found is printed, a copy is kept, and the answer decides.
///
public enum Confirmation {
    ///
    /// Ask whether the inventory may be removed.
    ///
    /// - Parameters:
    ///     - inventory: What was found on this machine.
    ///     - isPreApproved: Whether the run was started with the approval already given, which is what continuous integration and repeated runs do.
    ///
    /// - Returns: `true` if the reset may go ahead.
    ///
    public static func approveReset(of inventory: ClientInventory, isPreApproved: Bool) -> Bool {
        Console.log(inventory.description)

        guard !isPreApproved else {
            Console.log("Continuing because \(RunEnvironment.allowDestructiveVariableName) is set.")

            return true
        }

        guard isatty(fileno(stdin)) == 1 else {
            Console.log("Refusing to remove anything without a confirmation. Set \(RunEnvironment.allowDestructiveVariableName)=1 to approve this up front.")

            return false
        }

        Console.log("A copy of the existing configuration is kept in the artifacts directory.")
        Console.ask("Type \"yes\" to remove the state listed above: ")

        guard let answer = readLine(strippingNewline: true)?.lowercased() else {
            return false
        }

        return answer == "yes"
    }
}
