#!/usr/bin/env bash
set -euo pipefail

# Simple shell style enforcement: run shellcheck on all shell scripts
# Optional: run shfmt if installed to format code

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Allow passing specific files; default to all scripts
if [ $# -gt 0 ]; then
  SCRIPTS=("$@")
else
  SCRIPTS=(scripts/*.sh)
fi

if command -v shellcheck > /dev/null 2>&1; then
  echo "Running shellcheck..."
  # Use project-level config if present
  shellcheck --version | head -n1
  if ! shellcheck --severity=style --color=always --shell=bash "${SCRIPTS[@]}"; then
    echo "[info] shellcheck reported issues (warnings/errors above)." >&2
  fi
  echo "Shellcheck completed."
else
  echo "[info] shellcheck not found. Install with: brew install shellcheck (macOS)" >&2
fi

if command -v shfmt > /dev/null 2>&1; then
  echo "Running shfmt (formatting in-place)..."
  shfmt -w -i 2 -ci -sr scripts/*.sh
  echo "shfmt completed."
else
  echo "[info] shfmt not found. Install with: brew install shfmt (macOS)" >&2
fi
