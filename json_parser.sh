#!/usr/bin/env bash
set -euo pipefail
VERSION="0.1.0"

INPUT=""
POS=0
LEN=0

init_parser() {
    INPUT="$1"
    POS=0
    LEN=${#INPUT}
}

peek_char() {
    if (( POS < LEN )); then
        printf '%s' "${INPUT:POS:1}"
    fi
}

consume_char() {
    local c
    c=$(peek_char)
    (( POS++ )) || true
    printf '%s' "$c"
}

skip_whitespace() {
    local c
    while (( POS < LEN )); do
        c="${INPUT:POS:1}"
        case "$c" in
            ' '|$'\t'|$'\n'|$'\r') (( POS++ )) ;;
            *) break ;;
        esac
    done
}

expect_char() {
    local expected="$1"
    local c
    c=$(consume_char)
    if [[ "$c" != "$expected" ]]; then
        printf 'error: expected %q, got %q at pos %d\n' "$expected" "$c" "$POS" >&2
        return 1
    fi
}

parse_null() {
    POS=$((POS + 4))
    printf 'null'
}

parse_value() {
    skip_whitespace
    local c
    c=$(peek_char)
    case "$c" in
        '{') parse_object ;;
        '[') parse_array ;;
        '"') parse_string ;;
        't'|'f') parse_bool ;;
        'n') parse_null ;;
        ''|*) parse_number ;;
    esac
}