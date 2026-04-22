# LO03 Projet 2026 - Bash File System Synchronizer

## Project Background

This repository is for a group project in an OS/Linux course.

The official specification is provided in `LO03-Projet-2026.pdf`.
That PDF is the main source of truth and must be followed carefully.

The project goal is to implement a **file system synchronizer** in **Bash** for **two directory trees located on the same machine**.

The synchronizer works with:
- two file trees: A and B
- one journal/log file describing the last successful synchronization

The implementation should stay as faithful as possible to the PDF statement.

---

## Main Objective

Build a Bash program that synchronizes two directory trees A and B using the previous synchronization journal.

The desired result is:
- if a file exists on one side, the corresponding file should also exist on the other side whenever synchronization succeeds
- synchronized files should be identical in:
  - content
  - metadata:
    - file type
    - permissions
    - size
    - last modification time

If the program cannot determine a safe synchronization action, it must report a conflict instead of making unsafe assumptions.

---

## Required Functional Behavior

### 1. Simple Synchronizer

For each relative path `p` in the union of A and B:

- if `p/A` is a directory and `p/B` is a regular file, or the opposite:
  - this is a conflict

- if both are directories:
  - continue recursively / continue processing descendants

- if both are regular files and they have the same mode, size, and modification time:
  - synchronization succeeds
  - nothing must be done

- if `p/A` matches the journal and `p/B` does not:
  - `p/B` changed
  - copy content, mode, and modification time from `p/B` to `p/A`

- if `p/B` matches the journal and `p/A` does not:
  - `p/A` changed
  - copy content, mode, and modification time from `p/A` to `p/B`

- if both are regular files and neither matches the journal:
  - this is a conflict

After synchronization, rewrite the journal with all regular files whose synchronization succeeded.

Important:
- the traversal order in A and B may differ
- do not rely on raw file system order
- process the union of relative paths safely

---

### 2. Enhanced Synchronizer with Content Comparison

When the simple synchronizer would report a conflict between two regular files, compare file contents.

If contents are identical:
- if metadata are also identical:
  - synchronization succeeds
  - nothing to do

- if one side metadata matches the journal and the other does not:
  - only metadata changed on one side
  - synchronize metadata only

- if contents are identical but metadata differ on both sides:
  - this is a metadata-only conflict
  - report it explicitly

If synchronization succeeds in one of these enhanced cases, the resulting state must be stored in the journal.

---

## Technical Constraints

- Language: **Bash**
- Environment: Linux
- Scope: synchronization only between two file trees on the same machine
- The program must be safe for paths containing spaces
- The code must be modular, readable, and suitable for student presentation
- Prefer safe shell practices:
  - `set -euo pipefail`
  - careful quoting
  - helper functions for major logic
  - temporary files and atomic rename for journal rewriting

---

## Expected Deliverables

Please create and maintain these deliverables:

1. `src/sync.sh`
   - main Bash synchronizer
   - executable from the command line

2. `README.md`
   - project overview
   - usage
   - options
   - examples
   - limitations

3. `tests/run_tests.sh`
   - automated local test runner
   - should create temporary test environments and validate behavior

4. `docs/design-notes.md`
   - design explanations
   - journal format
   - synchronization rules
   - conflict categories
   - implementation notes

5. `docs/report-outline.md`
   - a clean report outline suitable for the course submission

6. `demo/demo.sh`
   - a simple demonstration script for presentation

---

## Recommended CLI

The command line should roughly follow:

```bash
bash src/sync.sh [options] DIR_A DIR_B LOG_FILE