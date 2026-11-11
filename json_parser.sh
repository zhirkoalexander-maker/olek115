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