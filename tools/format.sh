#!/bin/bash
# Format project-owned Objective-C sources. Build products are excluded.
set -euo pipefail
cd "$(dirname "$0")/.."

format_args=(-i)
case "${1:-}" in
    --check) format_args=(--dry-run --Werror) ;;
    '') ;;
    *) printf 'Usage: bash tools/format.sh [--check]\n' >&2; exit 2 ;;
esac

rg --files --null App Shared Helper Tests -g '*.h' -g '*.m' |
    xargs -0 clang-format --style=file "${format_args[@]}"
