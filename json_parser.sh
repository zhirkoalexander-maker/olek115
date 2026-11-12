#!/usr/bin/env bash
export LC_ALL=C
set -euo pipefail

INPUT=""
POS=0
LEN=0
CH=""
VAL=""
DEPTH=0
SOURCE=""

VERSION="1.0.0"
MAX_DEPTH=128
MAX_SIZE=1000000

MODE=flat
VALIDATE_ONLY=0
QUIET=0
SORT_OUTPUT=0
FILTER=""
SHOW_TYPES=0
SHOW_PATHS_ONLY=0
COUNT_ONLY=0
PRETTY=0
ALLOW_DUPLICATE_KEYS=0
ALLOW_TRAILING_COMMA=0
ALLOW_COMMENTS=0

N_TYPE=()
N_PATH=()
N_VALUE=()
N_KEY=()
N_KIDS=()
LEAVES=()
ROOT_ID=0
N_ID=0

peek_char() {
    CH=""
    if (( POS < LEN )); then
        CH="${INPUT:POS:1}"
    fi
}

consume_char() {
    peek_char
    if (( POS < LEN )); then
        POS=$((POS + 1))
    fi
}

skip_whitespace() {
    while (( POS < LEN )); do
        peek_char
        case "$CH" in
            ' '|$'\t'|$'\n'|$'\r') POS=$((POS + 1)) ;;
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
        expect_char "${word:i:1}" || return 1
    done
}

init_parser() {
    INPUT="$1"
    INPUT="${INPUT#$'\xEF\xBB\xBF'}"
    if (( ${#INPUT} > MAX_SIZE )); then
        printf 'error: input too large\n' >&2
        exit 1
    fi
    strip_comments
    POS=0
    LEN=${#INPUT}
    DEPTH=0
}

strip_comments() {
    if (( ! ALLOW_COMMENTS )); then
        return
    fi
    local out=""
    local i=0
    local len=${#INPUT}
    local instring=0
    while (( i < len )); do
        if (( instring )); then
            if [[ "${INPUT:i:1}" == '\' ]]; then
                out+=${INPUT:i:2}
                i=$((i + 2))
                continue
            fi
            if [[ "${INPUT:i:1}" == '"' ]]; then
                instring=0
            fi
            out+=${INPUT:i:1}
            i=$((i + 1))
            continue
        fi
        if (( i + 1 < len )) && [[ "${INPUT:i:2}" == '//' ]]; then
            while (( i < len )) && [[ "${INPUT:i:1}" != $'\n' ]]; do
                i=$((i + 1))
            done
        elif (( i + 1 < len )) && [[ "${INPUT:i:2}" == '/*' ]]; then
            i=$((i + 2))
            while (( i + 1 < len )) && [[ "${INPUT:i:2}" != '*/' ]]; do
                i=$((i + 1))
            done
            if (( i + 1 >= len )); then
                printf 'error: unterminated comment at pos %d\n' "$i" >&2
                return 1
            fi
            i=$((i + 2))
        else
            if [[ "${INPUT:i:1}" == '"' ]]; then
                instring=1
            fi
            out+=${INPUT:i:1}
            i=$((i + 1))
        fi
    done
    INPUT="$out"
}

add_node() {
    local type="$1"
    local path="$2"
    local value="$3"
    local key="$4"
    N_TYPE+=("$type")
    N_PATH+=("$path")
    N_VALUE+=("$value")
    N_KEY+=("$key")
    N_KIDS+=("")
    N_ID=$(( ${#N_TYPE[@]} ))
}

add_leaf() {
    add_node "$1" "$2" "$3" "$4"
    LEAVES+=("$N_ID")
}

node_kids() {
    local kids="${N_KIDS[$(( $1 - 1 ))]}"
    printf '%s' "$kids"
}

node_has_kids() {
    local kids="${N_KIDS[$(( $1 - 1 ))]}"
    if [[ -z "$kids" ]]; then
        return 1
    fi
    return 0
}

parse_null() {
    local path="$1"
    expect_word 'null' || return 1
    add_leaf null "$path" 'null' ""
}

parse_bool() {
    local path="$1"
    peek_char
    if [[ "$CH" == 't' ]]; then
        expect_word 'true' || return 1
        add_leaf boolean "$path" 'true' ""
    else
        expect_word 'false' || return 1
        add_leaf boolean "$path" 'false' ""
    fi
}

parse_number() {
    local path="$1"
    local num=""
    while (( POS < LEN )); do
        peek_char
        case "$CH" in
            '-'|[0-9]|'.'|'e'|'E'|'+') num+="$CH"; POS=$((POS + 1)) ;;
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
    add_leaf number "$path" "$num" ""
}

decode_escape_u() {
    local hex="${INPUT:POS+1:4}"
    if [[ ! "$hex" =~ ^[0-9a-fA-F]{4}$ ]]; then
        printf 'error: bad unicode escape at pos %d\n' "$POS" >&2
        return 1
    fi
    local cp=$((16#$hex))
    if (( cp >= 0xD800 && cp <= 0xDBFF )); then
        local pair="${INPUT:POS+5:6}"
        if [[ ! "$pair" =~ ^\\u[0-9a-fA-F]{4}$ ]]; then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
            return 1
        fi
        local low=$((16#${pair:2:4}))
        if (( low < 0xDC00 || low > 0xDFFF )); then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
            return 1
        fi
        cp=$((0x10000 + ((cp - 0xD800) * 1024) + (low - 0xDC00)))
        POS=$((POS + 6))
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
    POS=$((POS + 4))
}

parse_string_raw() {
    expect_char '"' || return 1
    local out=""
    while (( POS < LEN )); do
        peek_char
        if [[ "$CH" == [[:cntrl:]] ]]; then
            printf 'error: control character in string at pos %d\n' "$POS" >&2
            return 1
        fi
        if [[ "$CH" == '"' ]]; then
            break
        fi
        if [[ "$CH" == '\' ]]; then
            POS=$((POS + 1))
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
                *)
                    printf 'error: bad escape %q at pos %d\n' "$CH" "$POS" >&2
                    return 1
                    ;;
            esac
        fi
        out+="$CH"
        POS=$((POS + 1))
    done
    expect_char '"' || return 1
    VAL="$out"
}

parse_string() {
    local path="$1"
    parse_string_raw || return 1
    add_leaf string "$path" "$VAL" ""
}

parse_object() {
    local path="$1"
    expect_char '{' || return 1
    skip_whitespace
    if (( DEPTH >= MAX_DEPTH )); then
        printf 'error: max depth exceeded\n' >&2
        return 1
    fi
    DEPTH=$((DEPTH + 1))
    add_node object "$path" "" ""
    local id="$N_ID"
    local keys=$'\n'
    peek_char
    if [[ "$CH" == '}' ]]; then
        expect_char '}' || return 1
        DEPTH=$((DEPTH - 1))
        add_leaf object "$path" '{}' ""
        N_ID="$id"
        return 0
    fi
    while true; do
        skip_whitespace
        peek_char
        if [[ "$CH" != '"' ]]; then
            printf 'error: expected object key at pos %d\n' "$POS" >&2
            return 1
        fi
        local keypos="$POS"
        parse_string_raw || return 1
        local key="$VAL"
        if (( ! ALLOW_DUPLICATE_KEYS )) && [[ "$keys" == *$'\n'"$key"$'\n'* ]]; then
            printf 'error: duplicate key %q at pos %d\n' "$key" "$keypos" >&2
            return 1
        fi
        keys+="$key"$'\n'
        skip_whitespace
        expect_char ':' || return 1
        skip_whitespace
        local childpath="$key"
        if [[ ! "$key" =~ ^[A-Za-z0-9_-]+$ ]]; then
            childpath="$(json_quote "$key")"
        fi
        if [[ -n "$path" ]]; then
            childpath="$path.$childpath"
        fi
        parse_value "$childpath" || return 1
        local child="$N_ID"
        N_KIDS[$(( id - 1 ))]="${N_KIDS[$(( id - 1 ))]} $child"
        N_KEY[$(( child - 1 ))]="$key"
        skip_whitespace
        peek_char
        if [[ "$CH" == ',' ]]; then
            POS=$((POS + 1))
            skip_whitespace
            peek_char
            if (( ALLOW_TRAILING_COMMA )) && [[ "$CH" == '}' ]]; then
                break
            fi
            continue
        elif [[ "$CH" == '}' ]]; then
            break
        else
            printf 'error: expected comma or closing brace at pos %d\n' "$POS" >&2
            return 1
        fi
    done
    expect_char '}' || return 1
    DEPTH=$((DEPTH - 1))
    N_ID="$id"
}

parse_array() {
    local path="$1"
    expect_char '[' || return 1
    skip_whitespace
    if (( DEPTH >= MAX_DEPTH )); then
        printf 'error: max depth exceeded\n' >&2
        return 1
    fi
    DEPTH=$((DEPTH + 1))
    add_node array "$path" "" ""
    local id="$N_ID"
    peek_char
    if [[ "$CH" == ']' ]]; then
        expect_char ']' || return 1
        DEPTH=$((DEPTH - 1))
        add_leaf array "$path" '[]' ""
        N_ID="$id"
        return 0
    fi
    local index=0
    while true; do
        skip_whitespace
        local childpath="[$index]"
        if [[ -n "$path" ]]; then
            childpath="$path[$index]"
        fi
        parse_value "$childpath" || return 1
        local child="$N_ID"
        N_KIDS[$(( id - 1 ))]="${N_KIDS[$(( id - 1 ))]} $child"
        index=$((index + 1))
        skip_whitespace
        peek_char
        if [[ "$CH" == ',' ]]; then
            POS=$((POS + 1))
            skip_whitespace
            peek_char
            if (( ALLOW_TRAILING_COMMA )) && [[ "$CH" == ']' ]]; then
                break
            fi
            continue
        elif [[ "$CH" == ']' ]]; then
            break
        else
            printf 'error: expected comma or closing bracket at pos %d\n' "$POS" >&2
            return 1
        fi
    done
    expect_char ']' || return 1
    DEPTH=$((DEPTH - 1))
    N_ID="$id"
}

parse_value() {
    local path="$1"
    skip_whitespace
    peek_char
    case "$CH" in
        '{') parse_object "$path" ;;
        '[') parse_array "$path" ;;
        '"') parse_string "$path" ;;
        't'|'f') parse_bool "$path" ;;
        'n') parse_null "$path" ;;
        -|[0-9]) parse_number "$path" ;;
        '')
            printf 'error: unexpected end of input at pos %d\n' "$POS" >&2
            return 1
            ;;
        *)
            printf 'error: unexpected character %q at pos %d\n' "$CH" "$POS" >&2
            return 1
            ;;
    esac
}

parse_document() {
    skip_whitespace
    parse_value "" || return 1
    ROOT_ID="$N_ID"
    skip_whitespace
    if (( POS < LEN )); then
        printf 'error: trailing data at pos %d: %q\n' "$POS" "${INPUT:POS:10}" >&2
        return 1
    fi
}

json_quote() {
    local text="$1"
    local out=""
    local i=0
    local len=${#text}
    while (( i < len )); do
        local ch="${text:i:1}"
        case "$ch" in
            '"') out+='\"' ;;
            '\') out+='\\' ;;
            $'\n') out+='\n' ;;
            $'\t') out+='\t' ;;
            $'\r') out+='\r' ;;
            $'\b') out+='\b' ;;
            $'\f') out+='\f' ;;
            *)
                if [[ "$ch" == [[:cntrl:]] ]]; then
                    out+=$(printf '\\u%04x' "'$ch")
                else
                    out+="$ch"
                fi
                ;;
        esac
        i=$((i + 1))
    done
    printf '"%s"' "$out"
}

json_compact() {
    local id="$1"
    local type="${N_TYPE[$(( id - 1 ))]}"
    case "$type" in
        object)
            local out="{"
            local first=1
            local kid
            for kid in $(node_kids "$id"); do
                if (( first )); then
                    first=0
                else
                    out+=","
                fi
                out+="$(json_quote "${N_KEY[$(( kid - 1 ))]}")"
                out+=":"
                out+="$(json_compact "$kid")"
            done
            out+="}"
            printf '%s' "$out"
            ;;
        array)
            local out="["
            local first=1
            local kid
            for kid in $(node_kids "$id"); do
                if (( first )); then
                    first=0
                else
                    out+=","
                fi
                out+="$(json_compact "$kid")"
            done
            out+="]"
            printf '%s' "$out"
            ;;
        string)
            json_quote "${N_VALUE[$(( id - 1 ))]}"
            ;;
        *)
            printf '%s' "${N_VALUE[$(( id - 1 ))]}"
            ;;
    esac
}

json_indent() {
    local level="$1"
    local pad=""
    local i
    for (( i = 0; i < level; i++ )); do
        pad+="  "
    done
    printf '%s' "$pad"
}

json_pretty() {
    local id="$1"
    local level="$2"
    local type="${N_TYPE[$(( id - 1 ))]}"
    case "$type" in
        object)
            if ! node_has_kids "$id"; then
                printf '{}'
                return
            fi
            printf '{\n'
            local total=0
            local kid
            for kid in $(node_kids "$id"); do
                total=$((total + 1))
            done
            local i=0
            for kid in $(node_kids "$id"); do
                i=$((i + 1))
                printf '%s%s: ' "$(json_indent $((level + 1)))" "$(json_quote "${N_KEY[$(( kid - 1 ))]}")"
                json_pretty "$kid" $((level + 1))
                if (( i < total )); then
                    printf ',\n'
                else
                    printf '\n'
                fi
            done
            printf '%s}' "$(json_indent $level)"
            ;;
        array)
            if ! node_has_kids "$id"; then
                printf '[]'
                return
            fi
            printf '[\n'
            local total=0
            local kid
            for kid in $(node_kids "$id"); do
                total=$((total + 1))
            done
            local i=0
            for kid in $(node_kids "$id"); do
                i=$((i + 1))
                printf '%s' "$(json_indent $((level + 1)))"
                json_pretty "$kid" $((level + 1))
                if (( i < total )); then
                    printf ',\n'
                else
                    printf '\n'
                fi
            done
            printf '%s]' "$(json_indent $level)"
            ;;
        string)
            json_quote "${N_VALUE[$(( id - 1 ))]}"
            ;;
        *)
            printf '%s' "${N_VALUE[$(( id - 1 ))]}"
            ;;
    esac
}

leaf_display() {
    local id="$1"
    local path="${N_PATH[$(( id - 1 ))]}"
    local type="${N_TYPE[$(( id - 1 ))]}"
    local value="${N_VALUE[$(( id - 1 ))]}"
    if [[ "$type" == "string" ]]; then
        value="$(json_quote "$value")"
    fi
    local shown="$path"
    if [[ -z "$shown" ]]; then
        shown="(root)"
    fi
    if (( SHOW_TYPES )); then
        printf '%s:%s=%s' "$shown" "$type" "$value"
    else
        printf '%s=%s' "$shown" "$value"
    fi
}

collect_output() {
    local id
    local line
    if (( ${#LEAVES[@]} == 0 )); then
        return
    fi
    for id in "${LEAVES[@]}"; do
        if [[ -n "$FILTER" ]]; then
            local path="${N_PATH[$(( id - 1 ))]}"
            if [[ "$path" != *"$FILTER"* ]]; then
                continue
            fi
        fi
        if (( SHOW_PATHS_ONLY )); then
            line="${N_PATH[$(( id - 1 ))]}"
            if [[ -z "$line" ]]; then
                line="(root)"
            fi
        else
            line="$(leaf_display "$id")"
        fi
        printf '%s\n' "$line"
    done
}

print_result() {
    if (( COUNT_ONLY )); then
        printf '%d\n' "${#LEAVES[@]}"
        return
    fi
    if [[ "$MODE" == "json" ]]; then
        if (( PRETTY )); then
            json_pretty "$ROOT_ID" 0
            printf '\n'
        else
            json_compact "$ROOT_ID"
            printf '\n'
        fi
        return
    fi
    local output
    output="$(collect_output)"
    if [[ -n "$output" ]]; then
        if (( SORT_OUTPUT )); then
            printf '%s\n' "$output" | sort
        else
            printf '%s\n' "$output"
        fi
    fi
}

usage() {
    printf 'usage: %s [options] [json|file]\n' "$0"
    printf '\n'
    printf 'modes:\n'
    printf '  (default)             key=value pairs, one per line\n'
    printf '  --paths               only the paths, one per line\n'
    printf '  --types               add the type of every value\n'
    printf '  --json                print the json back, rebuilt from the tree\n'
    printf '  --pretty              indent the --json output\n'
    printf '  --count               print how many values were found\n'
    printf '\n'
    printf 'options:\n'
    printf '  -h, --help            show this help\n'
    printf '  -v, --version         show version\n'
    printf '  -q, --quiet           no output, only exit status\n'
    printf '  --validate            check the json and exit\n'
    printf '  --sort                sort the output lines\n'
    printf '  --filter TEXT         keep only paths containing TEXT\n'
    printf '  --max-depth N         nesting depth limit (default %d)\n' "$MAX_DEPTH"
    printf '  --max-size N          input size limit in bytes (default %d)\n' "$MAX_SIZE"
    printf '  --allow-duplicate-keys accept duplicate object keys\n'
    printf '  --allow-trailing-comma accept a trailing comma\n'
    printf '  --allow-comments      accept // and /* */ comments\n'
    printf '\n'
    printf 'the json can be an argument, a file path, or read from stdin\n'
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                printf 'json_parser %s\n' "$VERSION"
                exit 0
                ;;
            -q|--quiet)
                QUIET=1
                ;;
            --validate)
                VALIDATE_ONLY=1
                ;;
            --paths)
                SHOW_PATHS_ONLY=1
                ;;
            --types)
                SHOW_TYPES=1
                ;;
            --json)
                MODE=json
                ;;
            --pretty)
                PRETTY=1
                MODE=json
                ;;
            --count)
                COUNT_ONLY=1
                ;;
            --sort)
                SORT_OUTPUT=1
                ;;
            --filter)
                if (( $# < 2 )); then
                    printf 'error: --filter needs a text\n' >&2
                    exit 2
                fi
                FILTER="$2"
                shift
                ;;
            --allow-duplicate-keys)
                ALLOW_DUPLICATE_KEYS=1
                ;;
            --allow-trailing-comma)
                ALLOW_TRAILING_COMMA=1
                ;;
            --allow-comments)
                ALLOW_COMMENTS=1
                ;;
            --max-depth)
                if (( $# < 2 )); then
                    printf 'error: --max-depth needs a number\n' >&2
                    exit 2
                fi
                MAX_DEPTH="$2"
                shift
                ;;
            --max-size)
                if (( $# < 2 )); then
                    printf 'error: --max-size needs a number\n' >&2
                    exit 2
                fi
                MAX_SIZE="$2"
                shift
                ;;
            --)
                shift
                break
                ;;
            -)
                break
                ;;
            -[0-9]*)
                break
                ;;
            -*)
                printf 'error: unknown option %s\n' "$1" >&2
                exit 2
                ;;
            *)
                break
                ;;
        esac
        shift
    done
    SOURCE="${1-}"
}

read_source() {
    local path="$1"
    if [[ -d "$path" ]]; then
        printf 'error: is a directory: %s\n' "$path" >&2
        exit 1
    fi
    if [[ -f "$path" ]]; then
        if [[ ! -r "$path" ]]; then
            printf 'error: cannot read file: %s\n' "$path" >&2
            exit 1
        fi
        cat "$path"
        return
    fi
    if [[ "$path" == *.json ]]; then
        printf 'error: no such file: %s\n' "$path" >&2
        exit 1
    fi
    printf '%s' "$path"
}

main() {
    parse_args "$@"
    local json=""
    if [[ -z "$SOURCE" || "$SOURCE" == '-' ]]; then
        json="$(cat)"
    else
        json="$(read_source "$SOURCE")"
    fi
    if [[ -z "${json//[[:space:]]/}" ]]; then
        printf 'error: empty input\n' >&2
        exit 1
    fi
    init_parser "$json"
    parse_document
    if (( VALIDATE_ONLY || QUIET )); then
        return 0
    fi
    print_result
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
