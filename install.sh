#!/usr/bin/env bash
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/json_parser.sh"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

usage() {
    printf 'usage: %s [install|uninstall]\n' "$0"
    printf '\n'
    printf '  install     put json_parser into %s\n' "$BIN_DIR"
    printf '  uninstall   remove it again\n'
}

if (( $# == 0 )); then
    usage
    exit 0
fi

case "$1" in
    install)
        if ! command -v curl >/dev/null 2>&1; then
            printf 'error: curl is required\n' >&2
            exit 1
        fi
        mkdir -p "$BIN_DIR"
        curl -fsSL "$RAW_URL" -o "$BIN_DIR/json_parser.sh"
        chmod +x "$BIN_DIR/json_parser.sh"
        printf 'installed json_parser to %s\n' "$BIN_DIR/json_parser.sh"
        if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
            printf '\nadd it to your PATH:\n'
            printf '  export PATH="$BIN_DIR:$PATH"\n'
        fi
        ;;
    uninstall)
        rm -f "$BIN_DIR/json_parser.sh"
        printf 'removed %s\n' "$BIN_DIR/json_parser.sh"
        ;;
    -h|--help)
        usage
        ;;
    *)
        printf 'error: unknown command %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac
