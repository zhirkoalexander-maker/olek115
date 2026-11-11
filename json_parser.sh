#!/usr/bin/env bash
set -euo pipefail

INPUT=""
POS=0
LEN=0
CH=""
VAL=""

init_parser() {
    INPUT="$1"
    POS=0
    LEN=${#INPUT}
}

peek_char() {
    CH=""
    if (( POS < LEN )) ; then
        CH="${INPUT:POS:1}"
    fi
}

consume_char() {
    peek_char
    if (( POS < LEN )) ; then
        POS=$((POS+1))
    fi
}

skip_whitespace() {
    while (( POS < LEN )); do
        peek_char
        case "$CH" in
            ' '|$'\t'|$'\n'|$'\r') POS=$((POS+1)) ;;
            *) break ;;
        esac
    done
}

expect_char() {
    local expected="$1"
    consume_char
    if [[ "$CH" != "$expected" ]]; then
        printf 'error: expected %q, got %q at pos %d\n' "$expected" "$CH" "$POS" >&2
        return 1
    fi
}

expect_word() {
    local word="$1"
    local i
    for (( i = 0; i < ${#word}; i++ )); do
        expect_char "${word:i:1}"
    done
}

parse_value() {
    skip_whitespace
    peek_char
    case "$CH" in
        '{') parse_object ;;
        '[') parse_array ;;
        '"') parse_string ;;
        't'|'f') parse_bool ;;
        'n') parse_null ;;
        ''|*) parse_number ;;
    esac
}

parse_null() {
    expect_word 'null'
    VAL='null'
}
