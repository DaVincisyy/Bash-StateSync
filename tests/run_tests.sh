#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
SYNC_SCRIPT="$ROOT_DIR/src/sync.sh"

TEST_TMP=""
TEST_COUNT=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

new_sandbox() {
    TEST_TMP=$(mktemp -d)
    mkdir -p "$TEST_TMP/A" "$TEST_TMP/B"
}

cleanup_sandbox() {
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        rm -rf -- "$TEST_TMP"
    fi
    TEST_TMP=""
}

run_test() {
    local name="$1"
    shift

    TEST_COUNT=$((TEST_COUNT + 1))
    printf 'TEST %02d: %s\n' "$TEST_COUNT" "$name"

    new_sandbox
    trap 'cleanup_sandbox' RETURN
    "$@"
    cleanup_sandbox
    trap - RETURN
}

run_sync() {
    local stdout_file="$1"
    local stderr_file="$2"
    shift 2

    bash "$SYNC_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file"
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    [[ "$actual" -eq "$expected" ]] || fail "expected exit code $expected, got $actual"
}

assert_contains() {
    local file="$1"
    local text="$2"
    grep -F -- "$text" "$file" >/dev/null 2>&1 || fail "expected '$text' in $file"
}

assert_not_contains() {
    local file="$1"
    local text="$2"
    if grep -F -- "$text" "$file" >/dev/null 2>&1; then
        fail "did not expect '$text' in $file"
    fi
}

assert_file_equals() {
    local left="$1"
    local right="$2"
    cmp -s -- "$left" "$right" || fail "file contents differ: $left vs $right"
}

assert_mode_equals() {
    local left="$1"
    local right="$2"
    local left_mode
    local right_mode

    left_mode=$(stat -Lc '%a' -- "$left")
    right_mode=$(stat -Lc '%a' -- "$right")
    [[ "$left_mode" == "$right_mode" ]] || fail "mode differs: $left_mode vs $right_mode"
}

assert_mtime_equals() {
    local left="$1"
    local right="$2"
    local left_mtime
    local right_mtime

    left_mtime=$(stat -Lc '%Y' -- "$left")
    right_mtime=$(stat -Lc '%Y' -- "$right")
    [[ "$left_mtime" == "$right_mtime" ]] || fail "mtime differs: $left_mtime vs $right_mtime"
}

make_file() {
    local path="$1"
    local content="$2"
    mkdir -p -- "$(dirname "$path")"
    printf '%s' "$content" >"$path"
}

set_file_state() {
    local path="$1"
    local mode="$2"
    local timestamp="$3"

    chmod "$mode" "$path"
    touch -t "$timestamp" "$path"
}

initial_sync() {
    local stdout_file="$TEST_TMP/initial.stdout"
    local stderr_file="$TEST_TMP/initial.stderr"

    run_sync "$stdout_file" "$stderr_file" "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"
}

test_identical_trees() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"

    make_file "$TEST_TMP/A/dir one/file.txt" "same-data"
    set_file_state "$TEST_TMP/A/dir one/file.txt" 640 202604071200
    mkdir -p "$TEST_TMP/B/dir one"
    cp --preserve=mode,timestamps "$TEST_TMP/A/dir one/file.txt" "$TEST_TMP/B/dir one/file.txt"

    run_sync "$stdout_file" "$stderr_file" "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"

    assert_contains "$stdout_file" "Synchronization succeeded."
    assert_contains "$stdout_file" "ACTIONS=0"
    assert_file_equals "$TEST_TMP/A/dir one/file.txt" "$TEST_TMP/B/dir one/file.txt"
}

test_only_a_changed() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"

    make_file "$TEST_TMP/A/data.txt" "base"
    cp --preserve=mode,timestamps "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    initial_sync

    make_file "$TEST_TMP/A/data.txt" "changed-on-a"
    set_file_state "$TEST_TMP/A/data.txt" 600 202604071210

    run_sync "$stdout_file" "$stderr_file" "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"

    assert_contains "$stdout_file" "Synchronization succeeded."
    assert_file_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    assert_mode_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    assert_mtime_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
}

test_only_b_changed() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"

    make_file "$TEST_TMP/A/data.txt" "base"
    cp --preserve=mode,timestamps "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    initial_sync

    make_file "$TEST_TMP/B/data.txt" "changed-on-b"
    set_file_state "$TEST_TMP/B/data.txt" 600 202604071220

    run_sync "$stdout_file" "$stderr_file" "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"

    assert_contains "$stdout_file" "Synchronization succeeded."
    assert_file_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    assert_mode_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
    assert_mtime_equals "$TEST_TMP/A/data.txt" "$TEST_TMP/B/data.txt"
}

test_both_changed_with_different_contents() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"
    local status

    make_file "$TEST_TMP/A/conflict.txt" "base"
    cp --preserve=mode,timestamps "$TEST_TMP/A/conflict.txt" "$TEST_TMP/B/conflict.txt"
    initial_sync

    make_file "$TEST_TMP/A/conflict.txt" "left-version"
    make_file "$TEST_TMP/B/conflict.txt" "right-version"
    set_file_state "$TEST_TMP/A/conflict.txt" 644 202604071230
    set_file_state "$TEST_TMP/B/conflict.txt" 600 202604071231

    set +e
    run_sync "$stdout_file" "$stderr_file" --enhanced "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"
    status=$?
    set -e

    assert_exit_code 2 "$status"
    assert_contains "$stderr_file" $'CONFLICT\tcontent-conflict\tconflict.txt'
    assert_not_contains "$stdout_file" "Synchronization succeeded."
}

test_both_changed_with_identical_contents() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"
    local status

    make_file "$TEST_TMP/A/same.txt" "base"
    cp --preserve=mode,timestamps "$TEST_TMP/A/same.txt" "$TEST_TMP/B/same.txt"
    initial_sync

    make_file "$TEST_TMP/A/same.txt" "new-shared-content"
    make_file "$TEST_TMP/B/same.txt" "new-shared-content"
    set_file_state "$TEST_TMP/A/same.txt" 600 202604071240
    set_file_state "$TEST_TMP/B/same.txt" 644 202604071241

    set +e
    run_sync "$stdout_file" "$stderr_file" --enhanced "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"
    status=$?
    set -e

    assert_exit_code 2 "$status"
    assert_contains "$stderr_file" $'CONFLICT\tmetadata-only-conflict\tsame.txt'
}

test_directory_file_type_conflict() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"
    local status

    mkdir -p "$TEST_TMP/A/node"
    make_file "$TEST_TMP/B/node" "plain-file"

    set +e
    run_sync "$stdout_file" "$stderr_file" "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"
    status=$?
    set -e

    assert_exit_code 2 "$status"
    assert_contains "$stderr_file" $'CONFLICT\ttype-conflict\tnode'
}

test_metadata_only_difference_same_content() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"

    make_file "$TEST_TMP/A/meta.txt" "same-bytes"
    cp --preserve=mode,timestamps "$TEST_TMP/A/meta.txt" "$TEST_TMP/B/meta.txt"
    initial_sync

    set_file_state "$TEST_TMP/B/meta.txt" 600 202604071250

    run_sync "$stdout_file" "$stderr_file" --enhanced "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"

    assert_contains "$stdout_file" "Synchronization succeeded."
    assert_file_equals "$TEST_TMP/A/meta.txt" "$TEST_TMP/B/meta.txt"
    assert_mode_equals "$TEST_TMP/A/meta.txt" "$TEST_TMP/B/meta.txt"
    assert_mtime_equals "$TEST_TMP/A/meta.txt" "$TEST_TMP/B/meta.txt"
}

test_different_traversal_order_between_a_and_b() {
    local stdout_file="$TEST_TMP/stdout"
    local stderr_file="$TEST_TMP/stderr"

    mkdir -p "$TEST_TMP/A/z-dir" "$TEST_TMP/A/a-dir"
    mkdir -p "$TEST_TMP/B/a-dir" "$TEST_TMP/B/z-dir"

    make_file "$TEST_TMP/A/z-dir/late.txt" "late"
    make_file "$TEST_TMP/A/a-dir/early.txt" "early"
    make_file "$TEST_TMP/B/a-dir/early.txt" "early"
    make_file "$TEST_TMP/B/z-dir/late.txt" "late"

    set_file_state "$TEST_TMP/A/z-dir/late.txt" 644 202604071300
    cp --preserve=mode,timestamps "$TEST_TMP/A/z-dir/late.txt" "$TEST_TMP/B/z-dir/late.txt"
    set_file_state "$TEST_TMP/A/a-dir/early.txt" 600 202604071301
    cp --preserve=mode,timestamps "$TEST_TMP/A/a-dir/early.txt" "$TEST_TMP/B/a-dir/early.txt"

    run_sync "$stdout_file" "$stderr_file" --verbose "$TEST_TMP/A" "$TEST_TMP/B" "$TEST_TMP/journal.tsv"

    assert_contains "$stdout_file" "SCANNED_PATHS=4"
    assert_contains "$stdout_file" "PATH=a-dir"
    assert_contains "$stdout_file" "PATH=a-dir/early.txt"
    assert_contains "$stdout_file" "PATH=z-dir"
    assert_contains "$stdout_file" "PATH=z-dir/late.txt"
    assert_contains "$stdout_file" "ACTIONS=0"
}

main() {
    [[ -x "$SYNC_SCRIPT" ]] || fail "sync script is not executable: $SYNC_SCRIPT"

    run_test "identical trees" test_identical_trees
    run_test "only A changed" test_only_a_changed
    run_test "only B changed" test_only_b_changed
    run_test "both changed with different contents" test_both_changed_with_different_contents
    run_test "both changed with identical contents" test_both_changed_with_identical_contents
    run_test "directory/file type conflict" test_directory_file_type_conflict
    run_test "metadata-only difference with same content" test_metadata_only_difference_same_content
    run_test "different traversal order between A and B" test_different_traversal_order_between_a_and_b

    printf 'All %d tests passed.\n' "$TEST_COUNT"
}

main "$@"
