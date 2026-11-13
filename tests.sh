#!/usr/bin/env bash
set -uo pipefail

PARSER="$(cd "$(dirname "$0")" && pwd)/json_parser.sh"
PASS=0
FAIL=0

check() {
    local name="$1"
    local input="$2"
    local expected="$3"
    local got
    got="$("$PARSER" "$input" 2>/dev/null)"
    if [[ "$got" == "$expected" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$name"
        printf '  input:    %s\n' "$input"
        printf '  expected: %s\n' "$expected"
        printf '  got:      %s\n' "$got"
    fi
}

check_error() {
    local name="$1"
    local input="$2"
    if "$PARSER" "$input" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$name"
        printf '  input:    %s\n' "$input"
        printf '  expected: an error\n'
    else
        PASS=$((PASS + 1))
    fi
}

check 'object'            '{"a":1}'                     'a=1'
check 'object many'       '{"a":1,"b":2}'               $'a=1\nb=2'
check 'object empty'      '{}'                          '(root)={}'
check 'object nested'     '{"a":{"b":2}}'               'a.b=2'
check 'object deep'       '{"a":{"b":{"c":1}}}'          'a.b.c=1'
check 'object spaces'     '{ "a" : 1 }'                 'a=1'
check 'object key space'  '{"a b":1}'                   '"a b"=1'
check 'object empty key'  '{"":1}'                      '""=1'
check 'object quote key'  '{"a\"b":1}'                  '"a\"b"=1'

check 'array'             '[1,2,3]'                     $'[0]=1\n[1]=2\n[2]=3'
check 'array empty'       '[]'                          '(root)=[]'
check 'array nested'      '[[1,2],3]'                   $'[0][0]=1\n[0][1]=2\n[1]=3'
check 'array objects'     '[{"a":1}]'                   '[0].a=1'
check 'array strings'     '["a","b"]'                   $'[0]="a"\n[1]="b"'
check 'array spaces'      '[ 1 , 2 ]'                   $'[0]=1\n[1]=2'
check 'array empty items' '[[],[]]'                     $'[0]=[]\n[1]=[]'

check 'string'            '"hello"'                     '(root)="hello"'
check 'string empty'      '""'                          '(root)=""'
check 'string quote'      '"a\"b"'                      '(root)="a\"b"'
check 'string backslash'  '"a\\b"'                      '(root)="a\\b"'
check 'string spaces'     '"a b"'                       '(root)="a b"'

check 'number int'        '42'                          '(root)=42'
check 'number zero'       '0'                           '(root)=0'
check 'number negative'   '-17'                         '(root)=-17'
check 'number float'      '3.14'                        '(root)=3.14'
check 'number exponent'   '1e3'                         '(root)=1e3'
check 'number exponent 2' '1E-3'                        '(root)=1E-3'

check 'true'              'true'                        '(root)=true'
check 'false'             'false'                       '(root)=false'
check 'null'              'null'                        '(root)=null'

check 'escape newline'    '"a\nb"'                      '(root)="a\nb"'
check 'escape tab'        '"a\tb"'                      '(root)="a\tb"'
check 'escape slash'      '"a\/b"'                      '(root)="a/b"'
check 'unicode'           '"é"'                   '(root)="é"'
check 'unicode cjk'       '"中"'                   '(root)="中"'
check 'unicode emoji'     '"\uD83D\uDE00"'               '(root)="😀"'

check 'empty container'   '{"a":{},"b":[]}'             $'a={}\nb=[]'
check 'mixed'            '{"a":1,"b":{"c":2},"d":[3]}'  $'a=1\nb.c=2\nd[0]=3'

check_error 'no value'        '{"a":}'
check_error 'no comma'        '{"a" 1}'
check_error 'no colon'       '{"a" 1}'
check_error 'trailing comma'  '{"a":1,}'
check_error 'unclosed array'  '[1,2'
check_error 'unclosed string' '"abc'
check_error 'trailing data'   '{"a":1} junk'
check_error 'leading zero'    '01'
check_error 'bad number'      '1.2.3'
check_error 'bad char'        'x'
check_error 'empty input'     ''
check_error 'blank input'     '   '
check_error 'duplicate key'   '{"a":1,"a":2}'
check_error 'bad escape'      '"\q"'
check_error 'unpaired surrogate' '"\uD83D"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
