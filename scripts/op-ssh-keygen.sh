#!/usr/bin/env bash
set -euo pipefail

# op-ssh-keygen.sh — 1Password SSH key helper
#
# What it does
#  1) Searches 1Password for an SSH Key item (by --title or --host), lets you reuse or create it.
#  2) Prints (and copies) the PUBLIC key and shows its fingerprint.
#     (This script no longer edits 1Password's SSH agent.toml.)
#
# Usage:
#  op-ssh-keygen.sh [--host HOST --user USER] [--title TITLE] [--vault VAULT]
#                   [--no-copy] [--rsa BITS]
#
# Exit codes: 1 usage | 2 dependency/op failure | 3 item failure

TITLE=""
HOST=""
USER_NAME=""
VAULT="Private"
DO_COPY=1
KEY_SPEC="ed25519"

usage() {
  sed -n '1,120p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --vault)
      VAULT="${2:-}"
      shift 2
      ;;
    --no-copy)
      DO_COPY=0
      shift
      ;;
    --rsa)
      KEY_SPEC="rsa:${2:-4096}"
      shift 2
      ;;
    -h | --help) usage ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      ;;
  esac
done

need() { command -v "$1" > /dev/null 2>&1 || {
  echo "Missing dependency: $1" >&2
  exit 2
}; }
need op
need jq
need ssh-keygen
op whoami > /dev/null 2>&1 || {
  echo "Not signed in. Run: op signin" >&2
  exit 2
}

# (Note: This script intentionally does not read or write agent.toml.)

# --- Key selection / creation ---
PATTERN="$TITLE"
[[ -z "$PATTERN" && -n "$HOST" ]] && PATTERN="$HOST"
echo ">>> 1Password SSH Key helper"
echo "    Vault   : $VAULT"
echo "    Search  : ${PATTERN:-<none>}"
echo "    New key : $KEY_SPEC"

items="$(op item list --vault "$VAULT" --categories 'SSH Key' --format json)" || {
  echo "op item list failed" >&2
  exit 2
}
tmp="$(mktemp)"
if [[ -n "$PATTERN" ]]; then
  jq -r --arg pat "$PATTERN" '.[] | select(.title | test($pat; "i")) | .title' <<< "$items" > "$tmp" || {
    echo "jq filter failed" >&2
    rm -f "$tmp"
    exit 2
  }
else
  jq -r '.[] | .title' <<< "$items" > "$tmp" || {
    echo "jq parse failed" >&2
    rm -f "$tmp"
    exit 2
  }
fi
titles=()
while IFS= read -r t; do [[ -n "$t" ]] && titles+=("$t"); done < "$tmp"
rm -f "$tmp"

chosen=""
create_new=0
if ((${#titles[@]})); then
  echo
  echo "Found existing SSH keys:"
  nl -w2 -s': ' < <(printf "%s\n" "${titles[@]}")
  echo " 0: Create new key"
  printf "Choose a number (default 0): "
  read -r ch || true
  if [[ "$ch" =~ ^[0-9]+$ ]] && ((ch >= 1 && ch <= ${#titles[@]})); then
    chosen="${titles[$((ch - 1))]}"
    echo ">>> Reusing: $chosen"
  else create_new=1; fi
else
  echo "No matches; will create a new key."
  create_new=1
fi

if ((create_new)); then
  if [[ -z "$TITLE" ]]; then
    [[ -z "$HOST" || -z "$USER_NAME" ]] && {
      echo "To create: --title OR both --host and --user" >&2
      exit 1
    }
    TITLE="SSH Key - ${HOST} - ${USER_NAME} - $(date +%Y%m%d)"
  fi
  echo ">>> Creating SSH key in 1Password"
  echo "    Title : $TITLE"
  echo "    Type  : $KEY_SPEC"
  if [[ "$KEY_SPEC" == ed25519 ]]; then
    op item create --category 'SSH Key' --title "$TITLE" --vault "$VAULT" > /dev/null
  else
    op item create --category 'SSH Key' --title "$TITLE" --vault "$VAULT" --ssh-generate-key "$KEY_SPEC" > /dev/null
  fi
  chosen="$TITLE"
fi

# --- Get item and print/copy public key ---
item_json="$(op item get "$chosen" --vault "$VAULT" --format json)" || {
  echo "op item get failed" >&2
  exit 3
}
pub_key="$(printf '%s' "$item_json" | jq -r '(.fields[]? | select((.label // .t // "")|ascii_downcase=="public key") | .value // .v)
                                             // (.sections[]?.fields[]? | select(.t=="public key") | .v)
                                             // empty')"
[[ -z "$pub_key" || "$pub_key" == null ]] && {
  echo "ERROR: Could not extract public key." >&2
  exit 3
}

tmp_pub="$(mktemp)"
trap 'rm -f "$tmp_pub"' EXIT
printf "%s\n" "$pub_key" > "$tmp_pub"
finger="$(ssh-keygen -lf "$tmp_pub" | awk '{print $2 " " $1}')"

echo
echo "Title      : $chosen"
echo "Vault      : $VAULT"
echo "Fingerprint: $finger"
echo
echo "$pub_key"
echo
if ((DO_COPY)) && command -v pbcopy > /dev/null 2>&1; then
  printf "%s" "$pub_key" | pbcopy
  echo "(Public key copied to clipboard)"
fi

echo
echo "Done."
