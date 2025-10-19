#!/usr/bin/env bash
set -euo pipefail

# op-gen-ssh-pubonly.sh — 1Password SSH key helper (TOML-compliant, no allowed-hosts)
#
# What it does
#  1) Searches 1Password for an SSH Key item (by --title or --host), lets you reuse or create it.
#  2) Prints (and copies) the PUBLIC key.
#  3) Adds a managed block to the 1Password SSH agent config (agent.toml) listing the item:
#       # BEGIN op-gen-ssh-pubonly:<title>|<vault>
#       [[ssh-keys]]
#       item = "<title>"
#       vault = "<vault>"
#       # END op-gen-ssh-pubonly:<title>|<vault>
#
# agent.toml location (search order; creates the first if none exist):
#   1) ~/.config/1Password/ssh/agent.toml      ← current default (macOS/Linux)
#   2) ~/Library/Group Containers/2BUA8C4S2C.com.1password/agent.toml  ← legacy macOS
#
# Usage:
#  op-gen-ssh-pubonly.sh [--host HOST --user USER] [--title TITLE] [--vault VAULT]
#                        [--no-copy] [--rsa BITS] [--no-agent] [--yes]
#
# Notes:
#  - Host scoping is NOT supported in agent.toml. If you need host restrictions,
#    set them in the 1Password SSH Key item UI (if available in your build).
#
# Exit codes: 1 usage | 2 dependency/op failure | 3 item failure

TITLE=""; HOST=""; USER_NAME=""; VAULT="Private"
DO_COPY=1; KEY_SPEC="ed25519"; NO_AGENT=0; ASSUME_YES=0

usage(){ sed -n '1,120p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="${2:-}"; shift 2 ;;
    --host) HOST="${2:-}"; shift 2 ;;
    --user) USER_NAME="${2:-}"; shift 2 ;;
    --vault) VAULT="${2:-}"; shift 2 ;;
    --no-copy) DO_COPY=0; shift ;;
    --rsa) KEY_SPEC="rsa:${2:-4096}"; shift 2 ;;
    --no-agent) NO_AGENT=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
need op; need jq; need ssh-keygen
op whoami >/dev/null 2>&1 || { echo "Not signed in. Run: op signin" >&2; exit 2; }

# --- locate agent.toml ---
find_agent_file() {
  local c1="$HOME/.config/1Password/ssh/agent.toml"
  local c2="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/agent.toml"
  if [[ -f "$c1" ]]; then echo "$c1"; return 0; fi
  if [[ -f "$c2" ]]; then echo "$c2"; return 0; fi
  mkdir -p "$(dirname "$c1")"
  : > "$c1"
  echo "$c1"
}
AGENT_FILE="$(find_agent_file)"

# --- Key selection / creation ---
PATTERN="$TITLE"; [[ -z "$PATTERN" && -n "$HOST" ]] && PATTERN="$HOST"
echo ">>> 1Password SSH Key helper"
echo "    Vault   : $VAULT"
echo "    Search  : ${PATTERN:-<none>}"
echo "    New key : $KEY_SPEC"

items="$(op item list --vault "$VAULT" --categories 'SSH Key' --format json)" || { echo "op item list failed" >&2; exit 2; }
tmp="$(mktemp)"
if [[ -n "$PATTERN" ]]; then
  jq -r --arg pat "$PATTERN" '.[] | select(.title | test($pat; "i")) | .title' <<<"$items" >"$tmp" || { echo "jq filter failed" >&2; rm -f "$tmp"; exit 2; }
else
  jq -r '.[] | .title' <<<"$items" >"$tmp" || { echo "jq parse failed" >&2; rm -f "$tmp"; exit 2; }
fi
titles=(); while IFS= read -r t; do [[ -n "$t" ]] && titles+=("$t"); done < "$tmp"; rm -f "$tmp"

chosen=""; create_new=0
if (( ${#titles[@]} )); then
  echo; echo "Found existing SSH keys:"
  nl -w2 -s': ' < <(printf "%s\n" "${titles[@]}")
  echo " 0: Create new key"
  printf "Choose a number (default 0): "; read -r ch || true
  if [[ "$ch" =~ ^[0-9]+$ ]] && (( ch>=1 && ch<=${#titles[@]} )); then
    chosen="${titles[$((ch-1))]}"; echo ">>> Reusing: $chosen"
  else create_new=1; fi
else
  echo "No matches; will create a new key."; create_new=1
fi

if (( create_new )); then
  if [[ -z "$TITLE" ]]; then
    [[ -z "$HOST" || -z "$USER_NAME" ]] && { echo "To create: --title OR both --host and --user" >&2; exit 1; }
    TITLE="SSH Key - ${HOST} - ${USER_NAME} - $(date +%Y%m%d)"
  fi
  echo ">>> Creating SSH key in 1Password"
  echo "    Title : $TITLE"
  echo "    Type  : $KEY_SPEC"
  if [[ "$KEY_SPEC" == ed25519 ]]; then
    op item create --category 'SSH Key' --title "$TITLE" --vault "$VAULT" >/dev/null
  else
    op item create --category 'SSH Key' --title "$TITLE" --vault "$VAULT" --ssh-generate-key "$KEY_SPEC" >/dev/null
  fi
  chosen="$TITLE"
fi

# --- Get item and print/copy public key ---
item_json="$(op item get "$chosen" --vault "$VAULT" --format json)" || { echo "op item get failed" >&2; exit 3; }
pub_key="$(printf '%s' "$item_json" | jq -r '(.fields[]? | select((.label // .t // "")|ascii_downcase=="public key") | .value // .v)
                                             // (.sections[]?.fields[]? | select(.t=="public key") | .v)
                                             // empty')"
[[ -z "$pub_key" || "$pub_key" == null ]] && { echo "ERROR: Could not extract public key." >&2; exit 3; }

tmp_pub="$(mktemp)"; trap 'rm -f "$tmp_pub"' EXIT; printf "%s\n" "$pub_key" > "$tmp_pub"
finger="$(ssh-keygen -lf "$tmp_pub" | awk '{print $2 " " $1}')"

echo; echo "Title      : $chosen"
echo   "Vault      : $VAULT"
echo   "Fingerprint: $finger"; echo; echo "$pub_key"; echo
if (( DO_COPY )) && command -v pbcopy >/dev/null 2>&1; then printf "%s" "$pub_key" | pbcopy; echo "(Public key copied to clipboard)"; fi

# --- Agent policy (marker blocks, exact-line matching; no allowed-hosts) ---
if (( NO_AGENT )); then echo; echo "(Skipping agent.toml changes due to --no-agent)"; exit 0; fi

marker="op-gen-ssh-pubonly:${chosen}|${VAULT}"
BEGIN_LINE="# BEGIN $marker"
END_LINE="# END $marker"

echo; echo ">>> 1Password SSH Agent policy"
echo "    File  : $AGENT_FILE"
echo "    Block : $marker"

# Show existing managed block (exact-line match)
current_block="$(awk -v begin="$BEGIN_LINE" -v end="$END_LINE" '
  $0 == begin { inside=1 }
  inside { print }
  $0 == end   { inside=0 }
' "$AGENT_FILE")" || true

if [[ -n "$current_block" ]]; then
  echo "Existing managed block found:"; echo "$current_block" | sed 's/^/  /'
else
  echo "No existing managed block for this key."
fi

# Confirm write (or replace) unless --yes
do_write=0
if (( ASSUME_YES )); then
  do_write=1
else
  printf "Add/replace this managed block in agent.toml? [Y/n]: "
  read -r ans || true; [[ "${ans,,}" =~ ^(y|yes|)$ ]] && do_write=1
fi

if (( do_write )); then
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -p "$AGENT_FILE" "${AGENT_FILE}.bak-${stamp}"

  # Remove existing managed block (exact-line delimiters), then append fresh one
  tmp_out="$(mktemp)"
  awk -v begin="$BEGIN_LINE" -v end="$END_LINE" '
    BEGIN { inside=0 }
    $0 == begin { inside=1; next }
    $0 == end   { inside=0; next }
    inside==0 { print }
  ' "$AGENT_FILE" > "$tmp_out"

  {
    echo "$BEGIN_LINE"
    echo "[[ssh-keys]]"
    echo "item = \"$chosen\""
    echo "vault = \"$VAULT\""
    echo "$END_LINE"
    echo
  } >> "$tmp_out"

  mv "$tmp_out" "$AGENT_FILE"
  echo; echo "agent.toml updated. Backup: ${AGENT_FILE}.bak-${stamp}"
  echo "Restart 1Password (or toggle the SSH Agent in Settings → Developer) to pick up changes."
fi

echo; echo "Done."

