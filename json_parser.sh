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
KEY_PATH=""
RESULTS=()
TYPES=()

VERSION="0.3.0"
MAX_DEPTH=128
MAX_SIZE=1000000
VALIDATE_ONLY=0
QUIET=0
ALLOW_DUPLICATE_KEYS=0
ALLOW_TRAILING_COMMA=0
ALLOW_COMMENTS=0

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
        expect_char "${word:i:1}"
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
        local pair="${INPUT:POS+5:6}"
        if [[ ! "$pair" =~ ^\\u[0-9a-fA-F]{4}$ ]]; then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" "$POS" >&2
            return 1
        fi
        local low=$((16#${pair:2:4}))
        if (( low < 0xDC00 || low > 0xDFFF )); then
            printf 'error: unpaired surrogate %s at pos %d\n' "$hex" >&2
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

parse_string() {
    expect_char '"'
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
    expect_char '"'
    VAL="$out"
}

parse_array() {
    expect_char '['
    skip_whitespace
    if (( DEPTH >= MAX_DEPTH )); then
        printf 'error: max depth exceeded\n' >&2
        return 1
    fi
    DEPTH=$((DEPTH + 1))
    peek_char
    if [[ "$CH" == ']' ]]; then
        expect_char ']'
        DEPTH=$((DEPTH - 1))
        VAL='[]'
        return
    fi
    local index=0
    while true; do
        skip_whitespace
        local astart="$POS"
        local saved_path="$KEY_PATH"
        KEY_PATH="$KEY_PATH[$index]"
        parse_value
        local aend="$POS"
        local araw="${INPUT:astart:aend-astart}"
        if [[ "${araw:0:1}" == '"' ]]; then
            RESULTS+=("$KEY_PATH=\"$(json_escape "$VAL")\"")
        elif [[ "$VAL" == '{}' || "$VAL" == '[]' ]]; then
            RESULTS+=("$KEY_PATH=$VAL")
        elif [[ "${araw:0:1}" == '{' || "${araw:0:1}" == '[' ]]; then
            :
        else
            RESULTS+=("$KEY_PATH=$araw")
        fi
        KEY_PATH="$saved_path"
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
    expect_char ']'
    DEPTH=$((DEPTH - 1))
    VAL=''
}
parse_object() {
    expect_char '{'
    skip_whitespace
    if (( DEPTH >= MAX_DEPTH )); then
        printf 'error: max depth exceeded\n' >&2
        return 1
    fi
    DEPTH=$((DEPTH + 1))
    local keys=$'\n'
    peek_char
    if [[ "$CH" == '}' ]]; then
        expect_char '}'
        DEPTH=$((DEPTH - 1))
        VAL='{}'
        return
    fi
    while true; do
        skip_whitespace
        peek_char
        if [[ "$CH" != '"' ]]; then
            printf 'error: expected object key at pos %d\n' "$POS" >&2
            return 1
        fi
        local keypos="$POS"
        parse_string
        local key="$VAL"
        if (( ! ALLOW_DUPLICATE_KEYS )) && [[ "$keys" == *$'\n'"$key"$'\n'* ]]; then
            printf 'error: duplicate key %q at pos %d\n' "$key" "$keypos" >&2
            return 1
        fi
        keys+="$key"$'\n'
        skip_whitespace
        expect_char ':'
        skip_whitespace
        local vstart="$POS"
        local saved_path="$KEY_PATH"
        KEY_PATH="$(child_path "$KEY_PATH" "$key")"
        parse_value
        local vend="$POS"
        local raw="${INPUT:vstart:vend-vstart}"
        if [[ "${raw:0:1}" == '"' ]]; then
            RESULTS+=("$KEY_PATH=\"$(json_escape "$VAL")\"")
        elif [[ "$VAL" == '{}' || "$VAL" == '[]' ]]; then
            RESULTS+=("$KEY_PATH=$VAL")
        elif [[ "${raw:0:1}" == '{' || "${raw:0:1}" == '[' ]]; then
            :
        else
            RESULTS+=("$KEY_PATH=$raw")
        fi
        KEY_PATH="$saved_path"
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
    expect_char '}'
    DEPTH=$((DEPTH - 1))
    VAL=''
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
        -|[0-9]) parse_number ;;
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
    KEY_PATH=""
    RESULTS=()
    skip_whitespace
    parse_value
    skip_whitespace
    if (( POS < LEN )); then
        printf 'error: trailing data at pos %d: %q\n' "$POS" "${INPUT:POS:10}" >&2
        return 1
    fi
}

print_result() {
    if [[ "$MODE" == 'json' || "$MODE" == 'pretty' ]]; then
        format_json
        return
    fi
    print_mode
}

usage() {
    printf 'usage: %s [options] [json|file]\n' "$0"
    printf '\n'
    printf 'modes:\n'
    printf '  (default)              path=value for every value\n'
    printf '  --paths                only the paths\n'
    printf '  --types                path with the type of the value\n'
    printf '  --count                how many values were found\n'
    printf '  --json                 print the json back in one line\n'
    printf '  --pretty               print the json back with indentation\n'
    printf '  --sort                 sort the output\n'
    printf '  --filter TEXT          keep only paths containing TEXT\n'
    printf '\n'
    printf 'options:\n'
    printf '  -h, --help, help       show this help\n'
    printf '  -v, --version           show version\n'
    printf '  -q, --quiet             no output, only exit status\n'
    printf '  --validate              check the json and exit\n'
    printf '  --max-depth N           nesting depth limit (default %d)\n' "$MAX_DEPTH"
    printf '  --max-size N            input size limit in bytes (default %d)\n' "$MAX_SIZE"
    printf '  --allow-duplicate-keys  accept duplicate object keys\n'
    printf '  --allow-trailing-comma  accept a trailing comma\n'
    printf '  --allow-comments        accept // and /* */ comments\n'
    printf '\n'
    printf 'the json can be an argument, a file path, or read from stdin\n'
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -h|--help|help)
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
                MODE=paths
                ;;
            --types)
                MODE=types
                ;;
            --count)
                MODE=count
                ;;
            --json)
                MODE=json
                ;;
            --pretty)
                MODE=pretty
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

# === new functions go here ===
format_json() {
    local text="$INPUT"
    local pretty=0
    if [[ "$MODE" == 'pretty' ]]; then
        pretty=1
    fi
    local out=""
    local indent=0
    local i=0
    local len=${#text}
    local instring=0
    local ch
    while (( i < len )); do
        ch="${text:i:1}"
        if (( instring )); then
            if [[ "$ch" == '\' ]]; then
                out+="${text:i:2}"
                i=$((i + 2))
                continue
            fi
            if [[ "$ch" == '"' ]]; then
                instring=0
            fi
            out+="$ch"
            i=$((i + 1))
            continue
        fi
        case "$ch" in
            '"')
                instring=1
                out+="$ch"
                ;;
            '{'|'[')
                local j=$((i + 1))
                while (( j < len )) && [[ "${text:j:1}" == [[:space:]] ]]; do
                    j=$((j + 1))
                done
                if [[ "${text:j:1}" == '}' || "${text:j:1}" == ']' ]]; then
                    out+="$ch${text:j:1}"
                    i=$((j + 1))
                    continue
                fi
                out+="$ch"
                if (( pretty )); then
                    out+=$'\n'
                    indent=$((indent + 1))
                    out+="$(indent_spaces "$indent")"
                fi
                ;;
            '}'|']')
                if (( pretty )); then
                    while [[ "$out" == *[[:space:]] ]]; do
                        out="${out%?}"
                    done
                    out+=$'\n'
                    indent=$((indent - 1))
                    out+="$(indent_spaces "$indent")"
                fi
                out+="$ch"
                ;;
            ',')
                out+="$ch"
                if (( pretty )); then
                    out+=$'\n'
                    out+="$(indent_spaces "$indent")"
                fi
                ;;
            ':')
                out+="$ch"
                if (( pretty )); then
                    out+=" "
                fi
                ;;
            ' '|[[:space:]])
                ;;
            *)
                out+="$ch"
                ;;
        esac
        i=$((i + 1))
    done
    printf '%s\n' "$out"
}

indent_spaces() {
    local n=$(( $1 * 2 ))
    local pad=""
    local j
    for (( j = 0; j < n; j++ )); do
        pad+=" "
    done
    printf '%s' "$pad"
}

MODE=flat
SORT_OUTPUT=0
FILTER=""

child_path() {
    local parent="$1"
    local key="$2"
    local path="$key"
    if [[ ! "$key" =~ ^[A-Za-z0-9_-]+$ ]]; then
        path="\"$(json_escape "$key")\""
    fi
    if [[ -n "$parent" ]]; then
        path="$parent.$path"
    fi
    printf '%s' "$path"
}

json_escape() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\n'/\\n}"
    text="${text//$'\t'/\\t}"
    text="${text//$'\r'/\\r}"
    printf '%s' "$text"
}

json_quote() {
    printf '"%s"' "$(json_escape "$1")"
}

sort_pairs() {
    local pairs=($1)
    local sorted
    sorted="$(printf '%s\n' "${pairs[@]}" | sort -t '=' -k1,1 | tr '\n' ' ')"
    printf '%s\n' "${sorted% }"
}

result_path() {
    local line="$1"
    if [[ "$line" != '"'* ]]; then
        printf '%s' "${line%%=*}"
        return
    fi
    local i=1
    local ch
    while (( i < ${#line} )); do
        ch="${line:i:1}"
        if [[ "$ch" == '\' ]]; then
            i=$((i + 2))
            continue
        fi
        if [[ "$ch" == '"' ]]; then
            break
        fi
        i=$((i + 1))
    done
    printf '%s' "${line:0:i+1}"
}

result_value() {
    local line="$1"
    local path
    path="$(result_path "$line")"
    printf '%s' "${line:${#path}+1}"
}

value_type() {
    local value="$1"
    if [[ "$value" == '"'* ]]; then
        printf 'string'
    elif [[ "$value" == 'true' || "$value" == 'false' ]]; then
        printf 'boolean'
    elif [[ "$value" == 'null' ]]; then
        printf 'null'
    elif [[ "$value" == '{}' ]]; then
        printf 'object'
    elif [[ "$value" == '[]' ]]; then
        printf 'array'
    else
        printf 'number'
    fi
}

print_root() {
    if [[ "${INPUT:0:1}" == '"' ]]; then
        printf '(root)="%s"\n' "$(json_escape "$VAL")"
    else
        printf '(root)=%s\n' "$VAL"
    fi
}

print_mode() {
    if (( ${#RESULTS[@]} == 0 )); then
        print_root
        return
    fi
    local line
    local path
    local value
    local out=""
    local count=0
    for line in "${RESULTS[@]}"; do
        path="$(result_path "$line")"
        value="$(result_value "$line")"
        if [[ -n "$FILTER" && "$path" != *"$FILTER"* ]]; then
            continue
        fi
        count=$((count + 1))
        case "$MODE" in
            paths) out+="$path"$'\n' ;;
            types) out+="$path:$(value_type "$value")=$value"$'\n' ;;
            *) out+="$path=$value"$'\n' ;;
        esac
    done
    if [[ "$MODE" == 'count' ]]; then
        printf '%d\n' "$count"
        return
    fi
    if (( SORT_OUTPUT )); then
        printf '%s' "$out" | sort
    else
        printf '%s' "$out"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
