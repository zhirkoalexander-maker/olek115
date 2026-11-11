#!/usr/bin/env bash
set -euo pipefail

INPUT=""
POS=0
LEN=0

init_parser() {
    INPUT="$1"
    POS=0
    LEN=${#INPUT}
}

peek_char() {
    if (( POS < LEN )) ; then
        printf '%s' "${INPUT:POS:1}"
    fi
}
