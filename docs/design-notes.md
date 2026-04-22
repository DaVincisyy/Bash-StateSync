# Design Notes

## Objective

Build a Bash program that synchronizes two local directory trees using a journal of the last successful synchronization.

The implementation follows `LO03-Projet-2026.pdf` as the main specification and remains conservative whenever the statement is ambiguous.

## Current Scope

The current implementation covers:

- CLI argument parsing and basic validation
- file kind detection
- stat-based metadata helpers
- normalized metadata records
- journal parsing and in-memory journal lookup
- deterministic scanning of the union of relative paths from both trees
- regular-file decision logic
- enhanced content comparison for regular-file conflicts
- copy and metadata-only actions for safe cases
- journal rewrite after successful synchronization

The current implementation does not yet cover:

- broader handling for one-sided directories beyond conservative conflicts
- richer user-facing conflict formatting
- support for symbolic links or other special file types

## File Kind Model

Each inspected path is classified into one of four kinds:

- `missing`
- `regular`
- `directory`
- `unsupported`

This keeps later decision logic explicit and conservative. Symbolic links and other special file types currently fall into `unsupported`.

## Metadata Helpers

For regular files, the script exposes helpers for the metadata required by `TASK.md`:

- mode
- size
- mtime

The `normalized_metadata` helper emits a tab-separated record:

```text
kind<TAB>mode<TAB>size<TAB>mtime
```

For non-regular paths, unavailable metadata fields are represented as `-`.

## Journal Format

The journal is a tab-separated text file with one regular file per line:

```text
relative/path<TAB>mode<TAB>size<TAB>mtime
```

Rules:

- only regular files are stored
- blank lines are ignored
- lines beginning with `#` are treated as comments
- spaces inside paths are supported
- tabs are reserved as separators and therefore are not supported inside path names

This format matches the current needs from `TASK.md`: the simple synchronizer compares regular files using mode, size, and modification time against the previous successful synchronization state.

## Journal Helpers

The script currently provides:

- `load_journal`: parse the journal file into Bash arrays
- `parse_journal_line`: validate and split one journal line
- `journal_has_entry`: test whether a relative path exists in the journal
- `journal_entry_count`: return the number of parsed entries
- `journal_entry_record`: return normalized journal metadata for one path
- `journal_entry_matches_file`: compare a real regular file with its stored journal metadata

The in-memory journal uses:

- an ordered path list for counting and iteration
- associative arrays keyed by relative path for mode, size, and mtime lookups

## Path Scanning Layer

The scanner builds the set of candidate paths to inspect by:

- listing relative paths under `DIR_A`
- listing relative paths under `DIR_B`
- merging both lists
- sorting and deduplicating them with `LC_ALL=C sort -u`

This avoids relying on traversal order being identical between both trees.

The current implementation provides:

- `scan_tree_relative_paths`: list relative paths under one root
- `build_scanned_paths`: populate the in-memory sorted union
- `scanned_path_count`: return the number of discovered paths
- `print_scanned_paths`: print the discovered relative paths for debugging

Paths containing spaces are supported because each path is handled as a single line and kept quoted throughout the shell code.

## Regular-File Decisions

The script now separates regular-file handling into two layers:

- simple decision logic
- enhanced decision logic

### Simple Decision Logic

For two regular files at the same relative path:

- if mode, size, and mtime are identical, the path is considered already synchronized
- if A matches the journal and B does not, copy B to A
- if B matches the journal and A does not, copy A to B
- otherwise, the simple logic reports a regular-file conflict

### Enhanced Decision Logic

Enhanced mode is applied to regular-file disagreements before the tool falls back to a simple regular-file conflict.

- if file contents differ, the result remains a regular content conflict
- if contents are identical and metadata are identical, the path succeeds with no action
- if contents are identical and one side matches the journal metadata, synchronize metadata only from the journal-matching side to the other side
- if contents are identical but neither side matches the journal metadata, report a metadata-only conflict

This matches the enhanced behavior described in `TASK.md` and reduces false conflicts caused by metadata drift when file contents are still equal.

## Conflict Categories

The current implementation emits explicit conflict categories:

- `type-conflict`: directory versus regular file
- `unsupported-type`: unsupported file type encountered
- `presence-conflict`: a path exists on only one side in a case where no safe non-destructive action is inferred
- `regular-conflict`: simple regular-file logic cannot determine a safe action
- `content-conflict`: enhanced comparison found different file contents
- `metadata-only-conflict`: contents match, but both sides changed metadata relative to the journal

Conflicts stop the run before any mutation is applied.

## Execution Model

The script uses a two-phase model:

- scan and decide all actions/conflicts first
- if there are no conflicts, execute file copy or metadata-only actions

After a successful run, the journal is rewritten from tree `A`, which is valid because successful actions are intended to leave both trees synchronized.

## Initial Decisions

- language: Bash
- shell mode: `set -euo pipefail`
- synchronization target: two directory trees on the same machine
- default ambiguity policy: prefer conflict over unsafe inference
- journal scope: regular files only

## Automated Validation

The repository includes `tests/run_tests.sh`, which currently covers:

- identical trees
- one-sided updates from A or B
- real content conflicts
- metadata-only conflicts
- metadata-only synchronization in enhanced mode
- type conflicts
- traversal-order independence
