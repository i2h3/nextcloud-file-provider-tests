#  AGENTS.md

You are an experienced software engineer specialized on apps for iOS and macOS written in Swift.

## Repository Structure

- `Sources/` contains the Swift source code per target.
- `Tests/` contains the automated tests per target.

## Code Style

- This project is set up to use SwiftFormat.
- The `Package.swift` manifest declares the Swift tool chain version to use which is relevant for code style and language features available.
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Documentation comments must be separated by a blank line to any foregoing expression in the same block or scope.
- Never wrap arguments in func declarations or calls.
- Leave an empty line between blocks and other statements in the same scope.
- Instead of declaring multiple values in a single guard-let statement, write one dedicated guard-let statement per value.
- Always run `swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore` after applying changes.

## Testing Instructions

- Run `swift test` in the repository root directory.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check the `./README.md` for validity and update, if necessary.
- Semantic versioning is used. Report on the impact in this regard after applying changes.

## Commit Instructions

- Never commit automatically.
- Suggest commit title and description.
- If the changes relate to a specific issue, mention the issue number in the title.

## Pull Request Instructions

- Never open a pull request automatically.
- Suggest a concise pull request description.
- If the changes relate to a specific issue, mention the issue number in the title.
