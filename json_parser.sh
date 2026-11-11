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