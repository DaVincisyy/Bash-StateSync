#!/usr/bin/env bash

set -euo pipefail

VERBOSE=0
ENHANCED_MODE=0
DIR_A=""
DIR_B=""
LOG_FILE=""
declare -a POSITIONAL_ARGS=()
declare -a JOURNAL_PATHS=()
declare -a SCANNED_PATHS=()
declare -A JOURNAL_MODE=()
declare -A JOURNAL_SIZE=()
declare -A JOURNAL_MTIME=()
TMP_ACTIONS_FILE=""
TMP_CONFLICTS_FILE=""

usage() {
    cat <<EOF
Usage: bash src/sync.sh [options] DIR_A DIR_B LOG_FILE

Synchronize two local directory trees using a journal of the last
successful synchronization.

Options:
  --enhanced   Enable content comparison for regular-file conflicts
  --verbose    Enable verbose output
  --help       Show this help message
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        printf '%s\n' "$*"
    fi
}

cleanup_tmp_files() {
    if [[ -n "$TMP_ACTIONS_FILE" && -e "$TMP_ACTIONS_FILE" ]]; then
        rm -f -- "$TMP_ACTIONS_FILE"
    fi
    if [[ -n "$TMP_CONFLICTS_FILE" && -e "$TMP_CONFLICTS_FILE" ]]; then
        rm -f -- "$TMP_CONFLICTS_FILE"
    fi
}

parse_args() {
    local arg
    POSITIONAL_ARGS=()

    for arg in "$@"; do
        case "$arg" in
            --enhanced)
                ENHANCED_MODE=1
                ;;
            --verbose)
                VERBOSE=1
                ;;
            --help)
                usage
                exit 0
                ;;
            --*)
                die "unknown option: $arg"
                ;;
            *)
                POSITIONAL_ARGS+=("$arg")
                ;;
        esac
    done

    if [[ "${#POSITIONAL_ARGS[@]}" -ne 3 ]]; then
        usage >&2
        exit 1
    fi

    DIR_A="${POSITIONAL_ARGS[0]}"
    DIR_B="${POSITIONAL_ARGS[1]}"
    LOG_FILE="${POSITIONAL_ARGS[2]}"
}

validate_inputs() {
    [[ -d "$DIR_A" ]] || die "DIR_A is not a directory: $DIR_A"
    [[ -d "$DIR_B" ]] || die "DIR_B is not a directory: $DIR_B"
    [[ -d "$(dirname "$LOG_FILE")" ]] || die "log directory does not exist: $(dirname "$LOG_FILE")"
}

require_dependencies() {
    command -v stat >/dev/null 2>&1 || die "required command not found: stat"
    command -v find >/dev/null 2>&1 || die "required command not found: find"
    command -v sort >/dev/null 2>&1 || die "required command not found: sort"
    command -v cmp >/dev/null 2>&1 || die "required command not found: cmp"
    command -v cp >/dev/null 2>&1 || die "required command not found: cp"
    command -v chmod >/dev/null 2>&1 || die "required command not found: chmod"
    command -v touch >/dev/null 2>&1 || die "required command not found: touch"
    command -v mktemp >/dev/null 2>&1 || die "required command not found: mktemp"
    command -v mv >/dev/null 2>&1 || die "required command not found: mv"
}

# Return one of:
# - missing
# - regular
# - directory
# - unsupported
#
# This keeps later synchronization logic explicit and conservative.
path_kind() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        printf 'missing\n'
    elif [[ -f "$path" ]]; then
        printf 'regular\n'
    elif [[ -d "$path" ]]; then
        printf 'directory\n'
    else
        printf 'unsupported\n'
    fi
}

# Metadata helpers are intentionally limited to stat-based values required
# by TASK.md: mode, size, and modification time.
file_mode() {
    stat -Lc '%a' -- "$1"
}

file_size() {
    stat -Lc '%s' -- "$1"
}

file_mtime() {
    stat -Lc '%Y' -- "$1"
}

# Print normalized metadata as a tab-separated record:
# kind<TAB>mode<TAB>size<TAB>mtime
#
# For non-regular paths, unavailable fields are emitted as "-".
normalized_metadata() {
    local path="$1"
    local kind

    kind=$(path_kind "$path")

    case "$kind" in
        regular)
            printf 'regular\t%s\t%s\t%s\n' \
                "$(file_mode "$path")" \
                "$(file_size "$path")" \
                "$(file_mtime "$path")"
            ;;
        directory)
            printf 'directory\t-\t-\t-\n'
            ;;
        missing)
            printf 'missing\t-\t-\t-\n'
            ;;
        unsupported)
            printf 'unsupported\t-\t-\t-\n'
            ;;
        *)
            die "internal error: unknown kind for path $path"
            ;;
    esac
}

metadata_matches_between_files() {
    local path_a="$1"
    local path_b="$2"

    [[ "$(file_mode "$path_a")" == "$(file_mode "$path_b")" ]] || return 1
    [[ "$(file_size "$path_a")" == "$(file_size "$path_b")" ]] || return 1
    [[ "$(file_mtime "$path_a")" == "$(file_mtime "$path_b")" ]]
}

file_contents_match() {
    local path_a="$1"
    local path_b="$2"
    cmp -s -- "$path_a" "$path_b"
}

journal_reset() {
    JOURNAL_PATHS=()
    JOURNAL_MODE=()
    JOURNAL_SIZE=()
    JOURNAL_MTIME=()
}

# Journal format:
# relative/path<TAB>mode<TAB>size<TAB>mtime
#
# The journal stores only regular files that were successfully synchronized.
# Tabs are field separators, so file names containing spaces are supported.
parse_journal_line() {
    local line="$1"
    local rel
    local mode
    local size
    local mtime
    local extra=""

    IFS=$'\t' read -r rel mode size mtime extra <<<"$line"

    [[ -n "$rel" ]] || die "journal line is missing a relative path"
    [[ -n "$mode" && -n "$size" && -n "$mtime" ]] || die "journal entry is incomplete for path: $rel"
    [[ -z "$extra" ]] || die "journal entry has too many fields for path: $rel"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "journal mode is invalid for path: $rel"
    [[ "$size" =~ ^[0-9]+$ ]] || die "journal size is invalid for path: $rel"
    [[ "$mtime" =~ ^[0-9]+$ ]] || die "journal mtime is invalid for path: $rel"

    printf '%s\t%s\t%s\t%s\n' "$rel" "$mode" "$size" "$mtime"
}

load_journal() {
    local journal_path="$1"
    local line
    local rel
    local mode
    local size
    local mtime

    journal_reset

    if [[ ! -e "$journal_path" ]]; then
        log "journal does not exist yet: $journal_path"
        return 0
    fi

    [[ -f "$journal_path" ]] || die "journal path is not a regular file: $journal_path"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "${line:0:1}" == "#" ]] && continue

        IFS=$'\t' read -r rel mode size mtime <<<"$(parse_journal_line "$line")"

        if [[ -v JOURNAL_MODE["$rel"] ]]; then
            die "duplicate journal entry for path: $rel"
        fi

        JOURNAL_PATHS+=("$rel")
        JOURNAL_MODE["$rel"]="$mode"
        JOURNAL_SIZE["$rel"]="$size"
        JOURNAL_MTIME["$rel"]="$mtime"
    done <"$journal_path"
}

journal_has_entry() {
    local rel="$1"
    [[ -v JOURNAL_MODE["$rel"] ]]
}

journal_entry_count() {
    printf '%s\n' "${#JOURNAL_PATHS[@]}"
}

journal_entry_matches_file() {
    local rel="$1"
    local path="$2"

    journal_has_entry "$rel" || return 1
    [[ "$(path_kind "$path")" == "regular" ]] || return 1
    [[ "${JOURNAL_MODE["$rel"]}" == "$(file_mode "$path")" ]] || return 1
    [[ "${JOURNAL_SIZE["$rel"]}" == "$(file_size "$path")" ]] || return 1
    [[ "${JOURNAL_MTIME["$rel"]}" == "$(file_mtime "$path")" ]]
}

# List relative paths below one tree, one per line, without relying on the
# filesystem's raw enumeration order. Paths are emitted relative to the tree root.
scan_tree_relative_paths() {
    local root_dir="$1"

    (
        cd "$root_dir"
        find . -mindepth 1 -printf '%P\n'
    )
}

# Build the sorted union of relative paths from A and B.
# This is the stable scanning layer required by the specification before any
# synchronization decisions are made.
build_scanned_paths() {
    mapfile -t SCANNED_PATHS < <(
        {
            scan_tree_relative_paths "$DIR_A"
            scan_tree_relative_paths "$DIR_B"
        } | LC_ALL=C sort -u
    )
}

scanned_path_count() {
    printf '%s\n' "${#SCANNED_PATHS[@]}"
}

append_action() {
    local action_type="$1"
    local rel="$2"
    local src_side="$3"
    local dst_side="$4"
    printf '%s\t%s\t%s\t%s\n' "$action_type" "$rel" "$src_side" "$dst_side" >>"$TMP_ACTIONS_FILE"
}

append_conflict() {
    local rel="$1"
    local category="$2"
    local detail="$3"
    printf '%s\t%s\t%s\n' "$rel" "$category" "$detail" >>"$TMP_CONFLICTS_FILE"
}

action_count() {
    if [[ ! -s "$TMP_ACTIONS_FILE" ]]; then
        printf '0\n'
        return 0
    fi
    wc -l <"$TMP_ACTIONS_FILE" | tr -d ' '
}

conflict_count() {
    if [[ ! -s "$TMP_CONFLICTS_FILE" ]]; then
        printf '0\n'
        return 0
    fi
    wc -l <"$TMP_CONFLICTS_FILE" | tr -d ' '
}

relative_path_in_tree() {
    local root="$1"
    local rel="$2"
    printf '%s/%s\n' "$root" "$rel"
}

ensure_parent_dir() {
    local path="$1"
    mkdir -p -- "$(dirname -- "$path")"
}

copy_file_state() {
    local src="$1"
    local dst="$2"

    ensure_parent_dir "$dst"
    cp --preserve=mode,timestamps -- "$src" "$dst"
}

apply_metadata_only() {
    local src="$1"
    local dst="$2"

    chmod --reference="$src" -- "$dst"
    touch -r "$src" -- "$dst"
}

side_root() {
    local side="$1"

    case "$side" in
        A) printf '%s\n' "$DIR_A" ;;
        B) printf '%s\n' "$DIR_B" ;;
        *) die "internal error: invalid side $side" ;;
    esac
}

execute_actions() {
    local action_type
    local rel
    local src_side
    local dst_side
    local src_path
    local dst_path

    while IFS=$'\t' read -r action_type rel src_side dst_side; do
        [[ -z "$action_type" ]] && continue
        src_path="$(relative_path_in_tree "$(side_root "$src_side")" "$rel")"
        dst_path="$(relative_path_in_tree "$(side_root "$dst_side")" "$rel")"

        case "$action_type" in
            copy)
                log "ACTION copy $src_side->$dst_side $rel"
                copy_file_state "$src_path" "$dst_path"
                ;;
            metadata)
                log "ACTION metadata $src_side->$dst_side $rel"
                apply_metadata_only "$src_path" "$dst_path"
                ;;
            *)
                die "internal error: unknown action type $action_type"
                ;;
        esac
    done <"$TMP_ACTIONS_FILE"
}

rewrite_journal() {
    local tmp_journal
    local rel
    local path

    tmp_journal=$(mktemp "${LOG_FILE}.tmp.XXXXXX")

    (
        cd "$DIR_A"
        find . -type f -printf '%P\n' | LC_ALL=C sort
    ) | while IFS= read -r rel; do
        path="$(relative_path_in_tree "$DIR_A" "$rel")"
        printf '%s\t%s\t%s\t%s\n' \
            "$rel" \
            "$(file_mode "$path")" \
            "$(file_size "$path")" \
            "$(file_mtime "$path")"
    done >"$tmp_journal"

    mv -- "$tmp_journal" "$LOG_FILE"
}

simple_regular_file_decision() {
    local rel="$1"
    local path_a="$2"
    local path_b="$3"
    local a_matches_journal=0
    local b_matches_journal=0

    if metadata_matches_between_files "$path_a" "$path_b"; then
        log "DECISION success/unchanged $rel"
        return 0
    fi

    if journal_entry_matches_file "$rel" "$path_a"; then
        a_matches_journal=1
    fi
    if journal_entry_matches_file "$rel" "$path_b"; then
        b_matches_journal=1
    fi

    if [[ "$a_matches_journal" -eq 1 && "$b_matches_journal" -eq 0 ]]; then
        append_action "copy" "$rel" "B" "A"
        log "DECISION copy B->A $rel"
        return 0
    fi

    if [[ "$a_matches_journal" -eq 0 && "$b_matches_journal" -eq 1 ]]; then
        append_action "copy" "$rel" "A" "B"
        log "DECISION copy A->B $rel"
        return 0
    fi

    return 1
}

# Enhanced mode reduces false conflicts by checking content equality before
# defaulting to full-file propagation or conflict.
enhanced_regular_file_decision() {
    local rel="$1"
    local path_a="$2"
    local path_b="$3"
    local a_matches_journal=0
    local b_matches_journal=0

    if journal_entry_matches_file "$rel" "$path_a"; then
        a_matches_journal=1
    fi
    if journal_entry_matches_file "$rel" "$path_b"; then
        b_matches_journal=1
    fi

    if file_contents_match "$path_a" "$path_b"; then
        if metadata_matches_between_files "$path_a" "$path_b"; then
            log "DECISION success/content-and-metadata-identical $rel"
            return 0
        fi

        if [[ "$a_matches_journal" -eq 1 && "$b_matches_journal" -eq 0 ]]; then
            append_action "metadata" "$rel" "A" "B"
            log "DECISION metadata A->B $rel"
            return 0
        fi

        if [[ "$a_matches_journal" -eq 0 && "$b_matches_journal" -eq 1 ]]; then
            append_action "metadata" "$rel" "B" "A"
            log "DECISION metadata B->A $rel"
            return 0
        fi

        append_conflict "$rel" "metadata-only-conflict" "contents match but both sides changed metadata"
        return 0
    fi

    if [[ "$a_matches_journal" -eq 1 && "$b_matches_journal" -eq 0 ]]; then
        append_action "copy" "$rel" "B" "A"
        log "DECISION copy B->A $rel"
        return 0
    fi

    if [[ "$a_matches_journal" -eq 0 && "$b_matches_journal" -eq 1 ]]; then
        append_action "copy" "$rel" "A" "B"
        log "DECISION copy A->B $rel"
        return 0
    fi

    append_conflict "$rel" "content-conflict" "regular files differ in content"
}

decide_regular_file_path() {
    local rel="$1"
    local path_a="$2"
    local path_b="$3"

    if [[ "$ENHANCED_MODE" -eq 1 ]]; then
        enhanced_regular_file_decision "$rel" "$path_a" "$path_b"
        return 0
    fi

    if simple_regular_file_decision "$rel" "$path_a" "$path_b"; then
        return 0
    fi

    append_conflict "$rel" "regular-conflict" "simple metadata rules cannot determine a safe action"
}

decide_path() {
    local rel="$1"
    local path_a
    local path_b
    local kind_a
    local kind_b

    path_a="$(relative_path_in_tree "$DIR_A" "$rel")"
    path_b="$(relative_path_in_tree "$DIR_B" "$rel")"
    kind_a="$(path_kind "$path_a")"
    kind_b="$(path_kind "$path_b")"

    case "$kind_a:$kind_b" in
        directory:directory)
            log "DECISION continue/directories $rel"
            ;;
        regular:regular)
            decide_regular_file_path "$rel" "$path_a" "$path_b"
            ;;
        directory:regular|regular:directory)
            append_conflict "$rel" "type-conflict" "directory versus regular file"
            ;;
        unsupported:*|*:unsupported)
            append_conflict "$rel" "unsupported-type" "unsupported file type encountered"
            ;;
        regular:missing)
            if journal_has_entry "$rel"; then
                append_conflict "$rel" "presence-conflict" "file missing on B and deletion is not inferred"
            else
                append_action "copy" "$rel" "A" "B"
                log "DECISION copy A->B new file $rel"
            fi
            ;;
        missing:regular)
            if journal_has_entry "$rel"; then
                append_conflict "$rel" "presence-conflict" "file missing on A and deletion is not inferred"
            else
                append_action "copy" "$rel" "B" "A"
                log "DECISION copy B->A new file $rel"
            fi
            ;;
        missing:directory|directory:missing)
            append_conflict "$rel" "presence-conflict" "directory exists on only one side"
            ;;
        *)
            append_conflict "$rel" "presence-conflict" "unhandled path state"
            ;;
    esac
}

decide_all_paths() {
    local rel

    for rel in "${SCANNED_PATHS[@]}"; do
        decide_path "$rel"
    done
}

print_scanned_paths() {
    local rel_path

    for rel_path in "${SCANNED_PATHS[@]}"; do
        printf 'PATH=%s\n' "$rel_path"
    done
}

print_foundation_summary() {
    printf 'Project foundation ready.\n'
    printf 'DIR_A=%s\n' "$DIR_A"
    printf 'DIR_B=%s\n' "$DIR_B"
    printf 'LOG_FILE=%s\n' "$LOG_FILE"
    printf 'ENHANCED_MODE=%s\n' "$ENHANCED_MODE"
    printf 'VERBOSE=%s\n' "$VERBOSE"
    printf 'JOURNAL_ENTRIES=%s\n' "$(journal_entry_count)"
    printf 'SCANNED_PATHS=%s\n' "$(scanned_path_count)"

    if [[ "$VERBOSE" -eq 1 ]]; then
        printf 'DIR_A_METADATA=%s\n' "$(normalized_metadata "$DIR_A")"
        printf 'DIR_B_METADATA=%s\n' "$(normalized_metadata "$DIR_B")"
        print_scanned_paths
    fi
}

print_conflicts() {
    local rel
    local category
    local detail

    while IFS=$'\t' read -r rel category detail; do
        [[ -z "$rel" ]] && continue
        printf 'CONFLICT\t%s\t%s\t%s\n' "$category" "$rel" "$detail" >&2
    done <"$TMP_CONFLICTS_FILE"
}

main() {
    parse_args "$@"
    validate_inputs
    require_dependencies
    load_journal "$LOG_FILE"
    build_scanned_paths

    TMP_ACTIONS_FILE=$(mktemp)
    TMP_CONFLICTS_FILE=$(mktemp)
    trap cleanup_tmp_files EXIT

    print_foundation_summary
    decide_all_paths

    if [[ "$(conflict_count)" -gt 0 ]]; then
        print_conflicts
        exit 2
    fi

    execute_actions
    rewrite_journal
    printf 'Synchronization succeeded.\n'
    printf 'ACTIONS=%s\n' "$(action_count)"
}

main "$@"
