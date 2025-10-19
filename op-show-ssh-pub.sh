#!/usr/bin/env bash
set -euo pipefail

# op-show-ssh-pub.sh
# Search 1Password for SSH keys by title pattern and (optionally) show the PUBLIC key.
# - Default vault: Private
# - Case-insensitive substring/regex match against item.title
# - If multiple matches, presents a menu to pick one
# - Copies the public key to clipboard (macOS pbcopy) unless --no-copy
#
# Usage:
#   op-show-ssh-pub.sh <pattern> [--vault VAULT] [--list-only] [--no-copy]
#
# Examples:
#   op-show-ssh-pub.sh sdr-host --list-only
#   op-show-ssh-pub.sh "media|router" --vault Private
#   op-show-ssh-pub.sh sdr-host            # prints key (if unique match) and copies to clipboard
#
# Requirements: op (1Password CLI), jq, ssh-keygen (for fingerprint), pbcopy (optional)

pattern="${1:-}"
vault="Private"
list_only=0
do_copy=1

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) vault="${2:-Private}"; shift 2;;
    --list-only) list_only=1; shift;;
    --no-copy) do_copy=0; shift;;
    -h|--help)
      sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -z "$pattern" ]]; then
  echo "Usage: op-show-ssh-pub.sh <pattern> [--vault VAULT] [--list-only] [--no-copy]" >&2
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
need_cmd op
need_cmd jq
need_cmd ssh-keygen

# Ensure signed-in to 1Password CLI
if ! op whoami >/dev/null 2>&1; then
  echo "You are not signed in to 1Password CLI. Run:  op signin" >&2
  exit 2
fi

# 1) Fetch once and *check* op’s exit status
items_json="$(op item list --vault "$vault" --categories "SSH Key" --format json)" || {
  echo "Failed: op item list (check CLI login and flags). Aborting." >&2
  exit 2
}

# 2) Filter with jq into a temp file (so we can check jq’s exit, too)
tmp_titles="$(mktemp)"
if ! jq -r --arg pat "$pattern" '.[] | select(.title | test($pat; "i")) | .title' \
     <<<"$items_json" >"$tmp_titles"; then
  echo "Failed: jq parse/filter. Aborting." >&2
  rm -f "$tmp_titles"
  exit 2
fi

# 3) Load titles without process substitution (Bash 3.2 compatible)
titles=()
while IFS= read -r line; do
  titles+=("$line")
done < "$tmp_titles"
rm -f "$tmp_titles"

count=${#titles[@]}
if (( count == 0 )); then
  echo "No SSH items found matching \"$pattern\" in vault \"$vault\"." >&2
  exit 1
fi

# Just list and exit if --list-only
if (( list_only )); then
  printf "Matches in vault \"%s\":\n" "$vault"
  nl -w2 -s': ' < <(printf "%s\n" "${titles[@]}")
  exit 0
fi

# Pick title to display (if more than one)
if (( count == 1 )); then
  title="${titles[0]}"
else
  printf "Multiple matches in vault \"%s\":\n" "$vault"
  nl -w2 -s': ' < <(printf "%s\n" "${titles[@]}")
  printf "Enter number to show (or 0 to cancel): "
  read -r idx
  if [[ ! "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > count )); then
    echo "Canceled." >&2
    exit 1
  fi
  title="${titles[$((idx-1))]}"
fi

# Retrieve public key from chosen item
item_json="$(op item get "$title" --vault "$vault" --format json)"
pub_key="$(printf '%s' "$item_json" | jq -r '(.fields[]? | select((.label // .t // "")|ascii_downcase=="public key") | .value // .v)
                                             // (.sections[]?.fields[]? | select(.t=="public key") | .v)
                                             // empty')"
if [[ -z "$pub_key" || "$pub_key" == "null" ]]; then
  echo "Could not extract public key from \"$title\"." >&2
  exit 3
fi

# Print key + fingerprint
tmppub="$(mktemp)"; trap 'rm -f "$tmppub"' EXIT
printf "%s\n" "$pub_key" > "$tmppub"
finger="$(ssh-keygen -lf "$tmppub" | awk '{print $2 " " $1}')"

echo "Title      : $title"
echo "Vault      : $vault"
echo "Fingerprint: $finger"
echo
echo "$pub_key"
echo

if (( do_copy )); then
  if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$pub_key" | pbcopy
    echo "(Public key copied to clipboard)"
  fi
fi
