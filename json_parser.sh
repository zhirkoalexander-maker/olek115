#!/usr/bin/env bash
export LC_ALL=C
set -euo pipefail

INPUT=""
POS=0
LEN=0
CH=""
VAL=""
VERSION="0.3.0"
MAX_DEPTH=128
MAX_SIZE=1000000
VALIDATE_ONLY=0
ALLOW_DUPLICATE_KEYS=0

init_parser() {
    INPUT="$1"
    INPUT="${INPUT#$'\xEF\xBB\xBF'}"
    if (( ${#INPUT} > MAX_SIZE )); then printf 'error: input too large\n' >&2; exit 1; fi
    POS=0
    LEN=${#INPUT}
    DEPTH=0
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
    if [[ -z "$CH" ]]; then
        printf 'error: unexpected end of input at pos %d\n' "$POS" >&2
        return 1
    fi
    if [[ "$CH" != "$expected" ]]; then
        printf 'error: expected %q, got %q at pos %d\n' "$expected" "$CH" "$((POS - ${#CH}))" >&2
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

decode_escape_u() {
    local hex="${INPUT:POS+1:4}"
    if [[ ! "$hex" =~ ^[0-9a-fA-F]{4}$ ]]; then
        printf 'error: bad unicode escape at pos %d\n' "$POS" >&2
        return 1
    fi
    local cp=$((16#$hex))
    if (( cp >= 0xD800 && cp <= 0xDBFF )); then
        local next="${INPUT:POS+5:6}"
        if [[ ! "$next" =~ ^\\u[0-9a-fA-F]{4}$ ]]; then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
            return 1
        fi
        local low=$((16#${next:2:4}))
        if (( low < 0xDC00 || low > 0xDFFF )); then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
            return 1
        fi
        cp=$((0x10000 + ((cp - 0xD800) * 1024) + (low - 0xDC00)))
        POS=$((POS+6))
    elif (( cp >= 0xDC00 && cp <= 0xDFFF )); then
        printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
        return 1
    fi
    if (( cp == 0 )); then
        printf 'error: unsupported unicode escape %s at pos %d\n' "$hex" "$POS" >&2
        return 1
    fi
    local bytes=""
    if (( cp < 0x80 )); then
        bytes=$(printf '\\%03o' "$cp")
    elif (( cp < 0x800 )); then
        bytes=$(printf '\\%03o\\%03o' "$((0xC0 | (cp >> 6)))" "$((0x80 | (cp & 0x3F)))")
    elif (( cp < 0x10000 )); then
        bytes=$(printf '\\%03o\\%03o\\%03o' "$((0xE0 | (cp >> 12)))" "$((0x80 | ((cp >> 6) & 0x3F)))" "$((0x80 | (cp & 0x3F)))")
    else
        bytes=$(printf '\\%03o\\%03o\\%03o\\%03o' "$((0xF0 | (cp >> 18)))" "$((0x80 | ((cp >> 12) & 0x3F)))" "$((0x80 | ((cp >> 6) & 0x3F)))" "$((0x80 | (cp & 0x3F)))")
    fi
    CH=$(printf '%b' "$bytes")
    POS=$((POS+4))
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
                u) decode_escape_u || return 1 ;;
                *) printf 'error: bad escape %q at pos %d\n' "$CH" "$POS" >&2; return 1 ;;
            esac
        fi
        out+="$CH"
        POS=$((POS+1))
    done
    expect_char '"'
    out="${out//\\/\\\\}"
    out="${out//\"/\\\"}"
    if ! printf '%s' "$out" | grep -q '^$' 2>/dev/null; then true; fi
    VAL="$out"
}

parse_array() {
    expect_char '['
    skip_whitespace
    if (( DEPTH++ >= MAX_DEPTH )); then printf 'error: max depth exceeded\n' >&2; return 1; fi
    local arr=()
    peek_char
    if [[ "$CH" == ']' ]]; then
        expect_char ']'
        VAL='[]'
        return
    fi
    while true; do
        skip_whitespace
        local astart="$POS"
        parse_value
        local aend="$POS"
        local araw="${INPUT:astart:aend-astart}"
        if [[ "${araw:0:1}" == '"' ]]; then arr+=("\"$VAL\""); else arr+=("$araw"); fi
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
    (( DEPTH-- ))
}

parse_object() {
    expect_char '{'
    skip_whitespace
    if (( DEPTH++ >= MAX_DEPTH )); then printf 'error: max depth exceeded\n' >&2; return 1; fi
    local obj=()
    local keys=$'\n'
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
            if (( ! ALLOW_DUPLICATE_KEYS )) && [[ "$keys" == *$'\n'"$key"$'\n'* ]]; then printf 'error: duplicate key %q at pos %d\n' "$key" "$((POS - ${#key} - 2))" >&2; return 1; fi
            keys+="$key"$'\n'
            skip_whitespace
            expect_char ':'
            skip_whitespace
            local vstart="$POS"
            parse_value
            local vend="$POS"
            local raw="${INPUT:vstart:vend-vstart}"
            if [[ "$key" == *[[:space:]=]* || "$key" == *\"* || -z "$key" ]]; then key="\"$key\""; fi
            if [[ "${raw:0:1}" == '"' ]]; then obj+=("$key=\"$VAL\""); else obj+=("$key=$raw"); fi
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
    (( DEPTH-- ))
}

parse_document() {
    skip_whitespace
    parse_value
    skip_whitespace
    if (( POS < LEN )); then
        printf 'error: trailing data at pos %d: %q\n' "$POS" "${INPUT:POS:10}" >&2
        return 1
    fi
}

main() {
    local json=""
if [[ "${1-}" == '-h' || "${1-}" == '--help' ]]; then printf 'usage: %s [json|file]  (dash or no argument reads stdin)\n       echo '"'"'{"a":1}'"'"' | %s\n       %s file.json\n       %s --validate '"'"'{"a":1}'"'"'\n       %s --max-depth N '"'"'{"a":1}'"'"'\n       %s --max-size N '"'"'{"a":1}'"'"'\n       %s --allow-duplicate-keys '"'"'{"a":1,"a":2}'"'"'\n' "$0" "$0" "$0" "$0"; exit 0; fi
    if [[ "${1-}" == '-v' || "${1-}" == '--version' ]]; then printf 'json_parser %s\n' "$VERSION"; exit 0; fi
    if [[ "${1-}" == '--validate' ]]; then VALIDATE_ONLY=1; shift; fi
    if [[ "${1-}" == '--max-depth' ]]; then MAX_DEPTH="$2"; shift 2; fi
    if [[ "${1-}" == '--max-size' ]]; then MAX_SIZE="$2"; shift 2; fi
    if [[ "${1-}" == '--allow-duplicate-keys' ]]; then ALLOW_DUPLICATE_KEYS=1; shift; fi
    if (( $# > 0 )) && [[ "$1" == -* ]] && [[ "$1" != '-' ]] && [[ "$1" != '--' ]]; then printf 'error: unknown option %s\n' "$1" >&2; exit 2; fi
    if (( $# > 0 )); then
        if [[ "$1" == '--' ]]; then
            shift
            if (( $# > 0 )); then
                if [[ "$1" == '-' ]]; then json=$(cat); elif [[ -d "$1" ]]; then printf 'error: is a directory: %s\n' "$1" >&2; exit 1; elif [[ -f "$1" && ! -r "$1" ]]; then printf 'error: cannot read file: %s\n' "$1" >&2; exit 1; elif [[ -f "$1" ]]; then json=$(cat "$1"); elif [[ "$1" == *.json ]]; then printf 'error: no such file: %s\n' "$1" >&2; exit 1; else json="$1"; fi
            else
                if [[ -t 0 ]]; then printf 'usage: %s [json|file]  (dash or no argument reads stdin)\n' "$0"; exit 0; else json=$(cat); fi
            fi
        elif [[ "$1" == '-' ]]; then json=$(cat); elif [[ -d "$1" ]]; then printf 'error: is a directory: %s\n' "$1" >&2; exit 1; elif [[ -f "$1" && ! -r "$1" ]]; then printf 'error: cannot read file: %s\n' "$1" >&2; exit 1; elif [[ -f "$1" ]]; then json=$(cat "$1"); elif [[ "$1" == *.json ]]; then printf 'error: no such file: %s\n' "$1" >&2; exit 1; else json="$1"; fi
    elif [[ -t 0 ]]; then
        printf 'usage: %s [json|file]  (dash or no argument reads stdin)\n' "$0"
        exit 0
    else
        json=$(cat)
    fi
    init_parser "$json"
    if [[ "${json//[[:space:]]/}" == '' ]]; then printf 'error: empty input\n' >&2; exit 1; fi
    parse_document
    if (( VALIDATE_ONLY )); then exit 0; fi
    if [[ "${INPUT:0:1}" == '"' ]]; then printf '"%s"\n' "$VAL"; else printf '%s\n' "$VAL"; fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
