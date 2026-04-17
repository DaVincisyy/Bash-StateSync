#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT

A_DIR="$WORK_DIR/A"
B_DIR="$WORK_DIR/B"
JOURNAL_FILE="$WORK_DIR/journal.tsv"

print_section() {
    printf '\n== %s ==\n' "$1"
}

print_tree_state() {
    local label="$1"
    local root="$2"

    printf '%s\n' "$label"
    (
        cd "$root"
        find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort
    ) || true
}

show_file_details() {
    local path="$1"
    if [[ -f "$path" ]]; then
        printf 'mode=%s size=%s mtime=%s path=%s\n' \
            "$(stat -Lc '%a' -- "$path")" \
            "$(stat -Lc '%s' -- "$path")" \
            "$(stat -Lc '%Y' -- "$path")" \
            "$path"
        printf 'content: '
        cat "$path"
        printf '\n'
    fi
}

mkdir -p "$A_DIR/docs" "$B_DIR/docs"

print_section "Préparation"
printf 'Répertoire de démonstration : %s\n' "$WORK_DIR"
printf 'A = %s\n' "$A_DIR"
printf 'B = %s\n' "$B_DIR"
printf 'Journal = %s\n' "$JOURNAL_FILE"

printf 'version-1\n' >"$A_DIR/docs/report.txt"
chmod 640 "$A_DIR/docs/report.txt"
touch -t 202604071500 "$A_DIR/docs/report.txt"

print_tree_state "État initial A :" "$A_DIR"
print_tree_state "État initial B :" "$B_DIR"

print_section "1. Première synchronisation"
bash "$ROOT_DIR/src/sync.sh" --verbose "$A_DIR" "$B_DIR" "$JOURNAL_FILE"
show_file_details "$A_DIR/docs/report.txt"
show_file_details "$B_DIR/docs/report.txt"

print_section "2. Modification uniquement dans B"
printf 'version-2-from-B\n' >"$B_DIR/docs/report.txt"
chmod 600 "$B_DIR/docs/report.txt"
touch -t 202604071505 "$B_DIR/docs/report.txt"

bash "$ROOT_DIR/src/sync.sh" --verbose "$A_DIR" "$B_DIR" "$JOURNAL_FILE"
show_file_details "$A_DIR/docs/report.txt"
show_file_details "$B_DIR/docs/report.txt"

print_section "3. Même contenu, métadonnées différentes"
touch -t 202604071510 "$B_DIR/docs/report.txt"
chmod 644 "$B_DIR/docs/report.txt"

bash "$ROOT_DIR/src/sync.sh" --enhanced --verbose "$A_DIR" "$B_DIR" "$JOURNAL_FILE"
show_file_details "$A_DIR/docs/report.txt"
show_file_details "$B_DIR/docs/report.txt"

print_section "4. Conflit réel de contenu"
printf 'version-3-from-A\n' >"$A_DIR/docs/report.txt"
printf 'version-3-from-B\n' >"$B_DIR/docs/report.txt"
touch -t 202604071515 "$A_DIR/docs/report.txt"
touch -t 202604071516 "$B_DIR/docs/report.txt"

set +e
bash "$ROOT_DIR/src/sync.sh" --enhanced --verbose "$A_DIR" "$B_DIR" "$JOURNAL_FILE" 2>&1
STATUS=$?
set -e

printf 'Code de retour attendu pour conflit : %s\n' "$STATUS"
show_file_details "$A_DIR/docs/report.txt"
show_file_details "$B_DIR/docs/report.txt"

print_section "Fin de démonstration"
print_tree_state "Contenu final de A :" "$A_DIR"
print_tree_state "Contenu final de B :" "$B_DIR"
