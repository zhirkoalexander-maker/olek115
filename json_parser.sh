#!/usr/bin/env bash
set -euo pipefail

INPUT=""
POS=0
LEN=0
CH=""
VAL=""
VERSION="0.1.0"

init_parser() {
    INPUT="$1"
    INPUT="${INPUT#$'\xEF\xBB\xBF'}"
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
        '') printf 'error: unexpected end of input at pos %d\n' "$POS" >&2; return 1 ;;
        -|[0-9]) parse_number ;;
        *) printf 'error: unexpected character %q at pos %d\n' "$CH" "$POS" >&2; return 1 ;;
    esac
}

parse_null() {
    expect_word 'null'
    VAL='null'
}

parse_bool() {
    peek_char
    if [[ "$CH" == 't' ]]; then
        expect_word 'true'
        VAL='true'
    else
        expect_word 'false'
        VAL='false'
    fi
}

parse_number() {
    local num=""
    while (( POS < LEN )); do
        peek_char
        case "$CH" in
            '-'|[0-9]|'.'|'e'|'E'|'+' ) num+="$CH"; POS=$((POS+1)) ;;
            *) break ;;
        esac
    done
    if [[ -z "$num" ]]; then
        printf 'error: invalid value at pos %d\n' "$POS" >&2
        return 1
    fi
    if [[ ! "$num" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
        printf 'error: invalid number %q at pos %d\n' "$num" "$POS" >&2
        return 1
    fi
    VAL="$num"
}

parse_string() {
    expect_char '"'
    local out=""
    while (( POS < LEN )); do
        peek_char
        if [[ "$CH" == [[:cntrl:]] ]]; then printf 'error: control character in string at pos %d\n' "$POS" >&2; return 1; fi
        if [[ "$CH" == '"' ]]; then
            break
        fi
        if [[ "$CH" == '\' ]]; then
            POS=$((POS+1))
            peek_char
            case "$CH" in
                n) CH=$'\n' ;;
                t) CH=$'\t' ;;
                r) CH=$'\r' ;;
                b) CH=$'\b' ;;
                f) CH=$'\f' ;;
                '"') CH='"' ;;
                '\') CH='\' ;;
                '/') CH='/' ;;
                u) printf 'error: unicode escapes not supported at pos %d\n' "$POS" >&2; return 1 ;;
                *) printf 'error: bad escape %q at pos %d\n' "$CH" "$POS" >&2; return 1 ;;
            esac
        fi
        out+="$CH"
        POS=$((POS+1))
    done
    expect_char '"'
    VAL="$out"
}

parse_array() {
    expect_char '['
    skip_whitespace
    local arr=()
    peek_char
    if [[ "$CH" == ']' ]]; then
        expect_char ']'
        VAL='[]'
        return
    fi
    while true; do
        parse_value
        arr+=("$VAL")
        skip_whitespace
        peek_char
        if [[ "$CH" == ',' ]]; then
            POS=$((POS+1))
            skip_whitespace
            continue
        elif [[ "$CH" == ']' ]]; then
            break
        else
            printf 'error: expected comma or closing bracket at pos %d\n' "$POS" >&2
            return 1
        fi
    done
    expect_char ']'
    VAL="${arr[*]}"
}

parse_object() {
    expect_char '{'
    skip_whitespace
    local obj=()
    peek_char
    if [[ "$CH" == '}' ]]; then
        expect_char '}'
        VAL='{}'
        return
    fi
    while true; do
        skip_whitespace
        peek_char
        if [[ "$CH" == '"' ]]; then
            parse_string
            local key="$VAL"
            skip_whitespace
            expect_char ':'
            parse_value
            obj+=("$key=$VAL")
        else
            printf 'error: expected object key at pos %d\n' "$POS" >&2
            return 1
        fi
        skip_whitespace
        peek_char
        if [[ "$CH" == ',' ]]; then
            POS=$((POS+1))
            continue
        elif [[ "$CH" == '}' ]]; then
            break
        else
            printf 'error: expected comma or closing brace at pos %d\n' "$POS" >&2
            return 1
        fi
    done
    expect_char '}'
    VAL="${obj[*]}"
}

parse_document() {
    skip_whitespace
    parse_value
    skip_whitespace
    if (( POS < LEN )); then
        printf 'error: trailing data at pos %d\n' "$POS" >&2
        return 1
    fi
}

main() {
    local json=""
    if [[ "${1-}" == '-h' || "${1-}" == '--help' ]]; then printf 'usage: %s [json|file]\n' "$0"; exit 0; fi
    if (( $# > 0 )); then
        if [[ -f "$1" ]]; then json=$(cat "$1"); else json="$1"; fi
    else
        json=$(cat)
    fi
    init_parser "$json"
    parse_document
    printf '%s\n' "$VAL"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
