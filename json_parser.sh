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

parse_bool() {
    local c
    c=$(peek_char)
    if [[ "$c" == "t" ]]; then
        POS=$((POS + 4))
        printf 'true'
    else
        POS=$((POS + 5))
        printf 'false'
    fi
}

parse_null() {
    POS=$((POS + 4))
    printf 'null'
}

parse_number() {
    local buf=""
    local c
    while (( POS < LEN )); do
        c="${INPUT:POS:1}"
        case "$c" in
            -|+|.|e|E|[0-9]) buf+="$c" ;;
            *) break ;;
        esac
        (( POS++ ))
    done
    printf '%s' "$buf"
}

parse_string() {
    (( POS++ ))
    local buf=""
    local c
    while (( POS < LEN )); do
        c="${INPUT:POS:1}"
        if [[ "$c" == '\' ]]; then
            (( POS++ ))
            c="${INPUT:POS:1}"
        elif [[ "$c" == '"' ]]; then
            (( POS++ ))
            printf '%s' "$buf"
            return 0
        fi
        buf+="$c"
        (( POS++ ))
    done
    printf 'error: unterminated string at pos %d\n' "$POS" >&2
    return 1
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