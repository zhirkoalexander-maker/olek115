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
