#!/usr/bin/env bash
set -euo pipefail

# Better diagnostics on error
trap 'echo "ERROR: exit $? at command: \"$BASH_COMMAND\"" >&2' ERR

# -----------------------------------------------------------------------------
# op-ssh-addhost.sh
# Add/update a host entry in ~/.ssh/config using a 1Password-managed SSH key.
#
# Usage:
#   op-ssh-addhost.sh --host <host> --user <user> [--pub-file <name>.pub] [options]
#
# Command-line arguments:
#   --host <host>            Host pattern (e.g. github.com or homeassistant.local) [required]
#   --user <user>            SSH user for the host [required]
#   --pub-file <path>        Local .pub file name or path (default: <host>_<type>.pub)
#   --hostname <name>        SSH HostName value (DNS or IP); defaults to --host
#   --vault <name>           1Password vault name (default: Private)
#   --type <t>               SSH key type when creating new (default: ed25519; options: ed25519|rsa2048|rsa3072|rsa4096)
#   --auto-alias             If host resolves to IPv4, also upsert a block for the IPv4
#   --dry-run                Preview changes; do not write files
#   --yes                    Assume 'yes' to prompts (non-interactive)
#   --force                  If local .pub exists and mismatches, backup+overwrite without prompt
#   --ssh-dir <dir>          Specify .ssh directory (default: $HOME/.ssh)
#   --set-git-signing-key    Set git commit signing key to match this SSH key (and gpg.format=ssh)
#   -h, --help               Show help and exit
#
# Behavior:
# - Ensures you're signed into 1Password CLI
# - Ensures a 1Password SSH key item exists ("SSH Key - <host> - <user>")
# - Retrieves its public key, writes/validates the local .pub file
# - Upserts one or two Host blocks (hostname and optional IPv4 alias)
# - If --set-git-signing-key is used, sets git commit signing key to match the SSH key
#
# macOS-compatible (no bash 4-only features).
# -----------------------------------------------------------------------------

# -------------------------- Defaults / Globals --------------------------------
VAULT="Private"
NEW_TYPE="ed25519" # for new key creation (ed25519 | rsa2048 | rsa3072 | rsa4096)
SSH_DIR=""
CONF_FILE=""

HOST=""      # --host (required)
HOSTNAME=""  # --hostname (optional; defaults to HOST)
USER_NAME="" # --user (required)
PUB_FILE=""  # --pub-file (required local .pub path)
AUTO_ALIAS=0 # --auto-alias (try to add IPv4 alias block)

DRY_RUN=0    # --dry-run
YES=0        # --yes (assume "yes" to prompts)
FORCE=0      # --force (overwrite mismatched local .pub without prompt)
SET_GIT_SIGNING_KEY=0 # --set-git-signing-key

# 1Password agent socket preferences (macOS first, fallback Linux)
AGENT_SOCK_NATIVE="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
AGENT_SOCK_FIXED="$HOME/.1password/agent.sock"
# Prefer macOS socket, then Linux socket, otherwise leave empty
if [ -S "$AGENT_SOCK_FIXED" ]; then
  AGENT_SOCK="$AGENT_SOCK_FIXED"
elif [ -S "$AGENT_SOCK_NATIVE" ]; then
  AGENT_SOCK="$AGENT_SOCK_NATIVE"
else
  AGENT_SOCK=""
fi

# -------------------------- Helper: require commands --------------------------
need() { command -v "$1" > /dev/null 2>&1 || {
  echo "Missing required command: $1" >&2
  exit 127
}; }

# Skip dependency checks if in test mode
if [ -z "${OPSSH_TEST_MODE:-}" ]; then
  need op
  need jq
  need ssh-keygen
  need awk
  need sed
  need grep
  need install
fi

# -------------------------- Temp files (lazy init) ----------------------------
# Create temp files only when needed (after argument parsing or on first use).
init_tempfiles() {
  # Respect pre-set vars (e.g., in tests) and only create if missing
  if [ -z "${TMPA:-}" ]; then
    TMPA="$(mktemp "${TMPDIR:-/tmp}/opsshA.XXXXXX" 2> /dev/null || mktemp -t opsshA.XXXXXX)"
  fi
  if [ -z "${TMPB:-}" ]; then
    TMPB="$(mktemp "${TMPDIR:-/tmp}/opsshB.XXXXXX" 2> /dev/null || mktemp -t opsshB.XXXXXX)"
  fi
  if [ -z "${TBLK:-}" ]; then
    TBLK="$(mktemp "${TMPDIR:-/tmp}/opblk.XXXXXX" 2> /dev/null || mktemp -t opblk.XXXXXX)"
  fi

  # Ensure mktemp succeeded
  if [ -z "${TMPA:-}" ] || [ -z "${TMPB:-}" ] || [ -z "${TBLK:-}" ]; then
    echo "mktemp failed to create temporary files" >&2
    exit 2
  fi

  # Setup cleanup trap once temp files exist
  cleanup_tmp() { rm -f "${TMPA:-}" "${TMPB:-}" "${TBLK:-}"; }
  trap cleanup_tmp EXIT
}

# -------------------------- Function Definitions ------------------------------
# -------------------------- 1Password sign-in ---------------------------------
ensure_op() {
  if command -v op > /dev/null 2>&1; then
    if op whoami > /dev/null 2>&1; then
      HAS_OP=1
      return 0
    fi
    echo "1Password CLI: not signed in — attempting 'op signin'..." >&2
    # Interactive sign-in; user may cancel. Suppress noisy output but keep prompts.
    if op signin > /dev/null 2>&1; then
      HAS_OP=1
      echo "1Password CLI: signed in." >&2
      return 0
    else
      HAS_OP=0
      echo "1Password CLI: sign-in failed or canceled; proceeding without 1P lookups." >&2
      return 1
    fi
  else
    HAS_OP=0
    return 1
  fi
}

# Original version of this function retained for reference
# ensure_op() {
#   if op whoami > /dev/null 2>&1; then
#     return 0
#   fi
#   cat >&2 << 'MSG'
# 1Password CLI: not signed in.
# 
# Interactive sign-in cannot be safely performed from this script. Please sign in
# in your current shell so this script can access 1Password items. Example (interactive):
# 
#   eval "$(op signin)"
# 
# After signing in, re-run this script.
# MSG
#   exit 1
# }

# Helper: fingerprint from a public key string
fp_from_pub() {
  # stdin: public key line
  local tmp out
  tmp="$(mktemp "${TMPDIR:-/tmp}/pubk.XXXXXX" 2> /dev/null || mktemp -t pubk.XXXXXX)"
  cat > "$tmp"
  # macOS ssh-keygen: -E sha256 for explicit format
  out="$(ssh-keygen -lf "$tmp" -E sha256 2> /dev/null || true)"
  rm -f "$tmp"
  if [ -n "${out:-}" ]; then
    printf "%s" "$(printf '%s' "$out" | awk '{print $2}')"
  else
    printf ""
  fi
}

# Helper: fingerprint from a .pub file path
fp_from_file() {
  local out
  out="$(ssh-keygen -lf "$1" -E sha256 2> /dev/null || true)"
  if [ -n "${out:-}" ]; then
    printf "%s" "$(printf '%s' "$out" | awk '{print $2}')"
  else
    printf ""
  fi
}

ensure_default_block() {
  # $1 = working config file (in-place)
  local f="$1"
  if grep -qE '^[[:space:]]*Host[[:space:]]+\*$' "$f"; then
    return 0
  fi
  cat >> "$f" << 'EOF'

Host *
EOF
  if [ -n "${AGENT_SOCK:-}" ]; then
    printf '  IdentityAgent %s\n' "$AGENT_SOCK" >> "$f"
  fi
  cat >> "$f" << 'EOF'
  # IMPORTANT: allow agent identities
  IdentitiesOnly no
EOF
}

render_host_block() {
  # args: host, hostName, user, pubFile, [aliases]
  local host="$1" hostName="$2" user="$3" pub="$4" aliases="$5"
  : > "$TBLK"
  {
    echo "# Managed by op-ssh-addhost.sh on $(date '+%Y-%m-%d %H:%M:%S')"
    if [ -n "$aliases" ]; then
      echo "Host $aliases"
    else
      echo "Host $host"
    fi
    [ -n "$hostName" ] && echo "  HostName $hostName"
    [ -n "$user" ] && echo "  User $user"
    [ -n "$pub" ] && echo "  IdentityFile $pub"
    echo "  IdentitiesOnly yes"
    if [ -n "${AGENT_SOCK:-}" ]; then
      echo "  IdentityAgent $AGENT_SOCK"
    fi
  } >> "$TBLK"
}

upsert_host_block() {
  # args: inFile, outFile, host
  local in="$1" out="$2" host="$3"
  awk -v host="$host" -v blkfile="$TBLK" '
    function is_host_line(line) { return (line ~ /^[[:space:]]*Host[[:space:]]+/) }

    BEGIN {
      inserted = 0
    }

    {
      line = $0
      if (!inserted && is_host_line(line) && line ~ /^[[:space:]]*Host[[:space:]]+\*$/) {
        # Insert new block before the first Host * block
        while ((getline L < blkfile) > 0) print L
        close(blkfile)
        print ""  # blank line after new block
        inserted = 1
      }

      if (is_host_line(line)) {
        h = line
        sub(/^[[:space:]]*Host[[:space:]]+/, "", h)
        n = split(h, a, /[[:space:]]+/)
        found = 0
        for (i = 1; i <= n; i++) if (a[i] == host) found = 1
        if (found) { skip = 1; next }       # start skipping old block
        else if (skip) { skip = 0 }         # we just left a block; resume printing
      }

      if (skip) {
        # End skipping if we hit a blank line or a comment; preserve those lines
        if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) {
          skip = 0
          print
        }
        else next
      }

      if (!skip) print
    }

    END {
      if (!inserted) {
        print ""  # blank line before new block
        while ((getline L < blkfile) > 0) print L
        close(blkfile)
      }
    }
  ' "$in" > "$out"
}

# -------------------------- Main execution ------------------------------------
# Skip main execution if in test mode (allows sourcing for function testing)
if [ -z "${OPSSH_TEST_MODE:-}" ]; then

  # -------------------------- Parse arguments -----------------------------------
  while [ $# -gt 0 ]; do
    case "$1" in
      --host)
        HOST="${2:-}"
        shift 2
        ;;
      --hostname)
        HOSTNAME="${2:-}"
        shift 2
        ;;
      --user)
        USER_NAME="${2:-}"
        shift 2
        ;;
      --pub-file)
        PUB_FILE="${2:-}"
        shift 2
        ;;
      --vault)
        VAULT="${2:-}"
        shift 2
        ;;
      --type)
        NEW_TYPE="${2:-}"
        shift 2
        ;; # ed25519 (default) or one of rsa sizes
      --auto-alias)
        AUTO_ALIAS=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes)
        YES=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --set-git-signing-key)
        SET_GIT_SIGNING_KEY=1
        shift
        ;;
      --ssh-dir)
        SSH_DIR="${2:-}"
        shift 2
        ;;
      -h | --help)
        cat << EOF
Usage: $(basename "$0") --host <host> --user <user> [--pub-file <name>.pub] [options]

Required:
  --host <host>          Host pattern (e.g. github.com or homeassistant.local)
  --user <user>          SSH user for the host

Optional:
  --pub-file <path>      Local .pub file name or path (default: <host>_<type>.pub)
  --hostname <name>      SSH HostName value (DNS or IP); defaults to --host
  --vault <name>         1Password vault name (default: Private)
  --type <t>             SSH key type when creating new (default: ed25519; options: ed25519|rsa2048|rsa3072|rsa4096)
  --auto-alias           If host resolves to IPv4, also upsert a block for the IPv4
  --dry-run              Preview changes; do not write files
  --yes                  Assume 'yes' to prompts (non-interactive)
  --force                If local .pub exists and mismatches, backup+overwrite without prompt
  --ssh-dir <dir>        Specify .ssh directory (default: \$HOME/.ssh)
EOF
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 2
        ;;
    esac
  done

  # Validate required args
  [ -n "$HOST" ] || {
    echo "Error: --host is required" >&2
    exit 2
  }
  [ -n "$USER_NAME" ] || {
    echo "Error: --user is required" >&2
    exit 2
  }
  # If PUB_FILE is not supplied, set default to <host>_<type>.pub
  if [ -z "$PUB_FILE" ]; then
    PUB_FILE="$HOST""_""$NEW_TYPE.pub"
  fi
  [ -n "$HOSTNAME" ] || HOSTNAME="$HOST"

  # Set default SSH_DIR if not provided
  if [ -z "$SSH_DIR" ]; then
    SSH_DIR="$HOME/.ssh"
  fi
  mkdir -p "$SSH_DIR"
  CONF_FILE="$SSH_DIR/config"

  # Expand leading ~ in PUB_FILE if present (so dirname and later operations work)
  case "$PUB_FILE" in
    ~/*) PUB_FILE="${PUB_FILE/#\~/$HOME}" ;;
    \$HOME/*) PUB_FILE="${PUB_FILE/#\$HOME/$HOME}" ;;
    /*) ;; # absolute path, leave as is
    *) PUB_FILE="$SSH_DIR/$PUB_FILE" ;;
  esac

  # -------------------------- 1Password sign-in ---------------------------------
  ensure_op

  # -------------------------- Title & echo header -------------------------------
  TITLE="SSH Key - ${HOST} - ${USER_NAME}"
  echo ">>> 1Password SSH Key helper"
  echo "    Vault   : ${VAULT}"
  echo "    Host    : ${HOST}"
  echo "    User    : ${USER_NAME}"
  echo "    Title   : ${TITLE}"
  echo "    New key : ${NEW_TYPE}"

  # -------------------------- Find or create 1P key -----------------------------
  item_id=""
  # Try to safely fetch item JSON and id; tolerate failures
  item_json="$(op item get "$TITLE" --vault "$VAULT" --format json 2> /dev/null || true)"
  item_id="$(printf '%s' "$item_json" | jq -r '.id // ""' 2> /dev/null || true)"
  if [ -n "${item_id:-}" ]; then
    echo "Using 1Password SSH Key: $TITLE"
  fi

  if [ -z "$item_id" ]; then
    echo "Creating 1Password SSH Key: $TITLE"
    # Map NEW_TYPE to op's accepted values
    case "$NEW_TYPE" in
      ed25519 | rsa2048 | rsa3072 | rsa4096) : ;;
      rsa) NEW_TYPE="rsa4096" ;; # be nice if user typed --type rsa
      *) NEW_TYPE="ed25519" ;;
    esac
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "(dry-run) Would create 1Password SSH Key: $TITLE"
    else
      # Correct flag is --ssh-generate-key=<type> and --category=ssh
      if ! op item create --category=ssh --title="$TITLE" --vault="$VAULT" \
        --ssh-generate-key="$NEW_TYPE" > /dev/null 2>&1; then
        echo "Failed to create 1Password SSH item: $TITLE" >&2
        exit 1
      fi
    fi
    # Re-fetch item_json and id robustly
    item_json="$(op item get "$TITLE" --vault "$VAULT" --format json 2> /dev/null || true)"
    item_id="$(printf '%s' "$item_json" | jq -r '.id // ""' 2> /dev/null || true)"
  fi

  # -------------------------- Get 1P public key & fingerprint -------------------
  ONEP_PUB=""
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry-run) Would fetch public key from 1Password item: $TITLE"
  else
    # Use previously fetched item_json if available, else fetch now
    if [ -z "${item_json:-}" ]; then
      item_json="$(op item get "$TITLE" --vault "$VAULT" --format json 2> /dev/null || true)"
    fi
    # Try to extract a field whose label contains 'public' (case-insensitive)
    ONEP_PUB="$(printf '%s' "$item_json" | jq -r '.fields[]? | select((.label|ascii_downcase) | test("public")) | .value' 2> /dev/null || true)"
    # Fallback: if not found, try to extract any field that looks like an SSH public key
    if [ -z "${ONEP_PUB:-}" ]; then
      ONEP_PUB="$(printf '%s' "$item_json" | jq -r '.fields[]?.value' 2> /dev/null || true | grep -E '^(ssh-|ecdsa-|sk-|ed25519-)' | head -n1 || true)"
    fi
  fi

  # -------------------------- Ensure local .pub exists & matches ----------------
  mkdir -p "$(dirname "$PUB_FILE")"

  if [ "$DRY_RUN" -eq 0 ]; then
    # Get 1P fingerprint
    ONEP_FP=""
    if [ -n "$ONEP_PUB" ]; then
      ONEP_FP="$(printf "%s\n" "$ONEP_PUB" | fp_from_pub)"
    fi
  else
    # In dry-run we can still compute 1P FP if we got it; otherwise leave empty
    ONEP_FP=""
  fi

  if [ -s "$PUB_FILE" ]; then
    # Local exists; compute local FP (robust even if file is wrong format)
    LOCAL_FP=""
    if grep -qE '^(ssh-|sk-ssh-)' "$PUB_FILE"; then
      LOCAL_FP="$(fp_from_file "$PUB_FILE" || true)"
    else
      # Fallback: try to compute from raw content (e.g., someone saved a single line)
      LOCAL_FP="$(cat "$PUB_FILE" | fp_from_pub || true)"
    fi

    # If both fingerprints exist and differ, prompt (unless --force/--yes)
    if [ -n "${ONEP_FP:-}" ] && [ -n "${LOCAL_FP:-}" ] && [ "$ONEP_FP" != "$LOCAL_FP" ]; then
      echo
      echo "Local public key ($PUB_FILE) does not match 1Password:"
      echo "  Local     : ${LOCAL_FP:-unknown}"
      echo "  1Password : ${ONEP_FP:-unknown}"
      echo
      if [ "$FORCE" -eq 1 ] || [ "$YES" -eq 1 ]; then
        choice=1
      else
        echo "  1) Backup and overwrite local .pub with 1Password key"
        echo "  2) Quit"
        printf "Choose [default: 2]: "
        # If running non-interactively, default to abort
        if [ -t 0 ]; then
          # wait up to 30s for user input
          read -t 30 -r choice || true
        else
          choice=2
        fi
      fi
      case "${choice:-2}" in
        1)
          if [ "$DRY_RUN" -eq 1 ]; then
            echo "(dry-run) Would backup and overwrite: $PUB_FILE"
          else
            cp -p "$PUB_FILE" "$PUB_FILE.bak.$(date +%Y%m%d%H%M%S)"
            printf "%s\n" "$ONEP_PUB" > "$PUB_FILE"
            chmod 644 "$PUB_FILE"
          fi
          ;;
        *)
          echo "Aborting."
          exit 1
          ;;
      esac
    elif [ "$FORCE" -eq 1 ] && [ -n "${ONEP_PUB:-}" ]; then
      # Force overwrite even if we couldn't compute fingerprints (e.g. bad local file)
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "(dry-run) Would backup and overwrite: $PUB_FILE"
      else
        cp -p "$PUB_FILE" "$PUB_FILE.bak.$(date +%Y%m%d%H%M%S)" || true
        printf "%s\n" "$ONEP_PUB" > "$PUB_FILE"
        chmod 644 "$PUB_FILE"
      fi
    fi
  else
    # No local file — create from 1P
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "(dry-run) Would write public key to: $PUB_FILE"
    else
      if [ -z "${ONEP_PUB:-}" ]; then
        echo "Could not retrieve public key from 1Password." >&2
        exit 1
      fi
      # atomic write to avoid partial files
      # portable mktemp in same dir as PUB_FILE
      tmp_pub_dir="$(dirname "$PUB_FILE")"
      tmp_pub="$(mktemp "$tmp_pub_dir/pubfile.XXXXXX" 2> /dev/null || mktemp -t pubfile.XXXXXX)"
      printf "%s\n" "$ONEP_PUB" > "$tmp_pub"
      mv "$tmp_pub" "$PUB_FILE"
      chmod 644 "$PUB_FILE"
    fi
  fi

  # -------------------------- Resolve IPv4 alias if requested -------------------
  HOST_IPV4=""
  if [ "$AUTO_ALIAS" -eq 1 ]; then
    # Try fast ping on macOS; fall back to dig
    # First, attempt to capture the IPv4 from PING header line.
  HOST_IPV4="$(ping -c1 "$HOST" 2> /dev/null | grep -oE '\([0-9.]+\)' | tr -d '()' | head -n1 || true)"
  if [ -z "$HOST_IPV4" ]; then
    if command -v dig > /dev/null 2>&1; then
      HOST_IPV4="$(dig +short "$HOST" A 2> /dev/null | head -n1 || true)"
    fi
  fi
    # If still empty, we'll just proceed without alias; not fatal.
  fi


  # -------------------------- Build new config (dry-run or write) ---------------
  # Initialize temp files now that arguments are processed
  init_tempfiles

  # Start from existing config (or empty)
  if [ -s "$CONF_FILE" ]; then
    cp -p "$CONF_FILE" "$TMPA"
  else
    : > "$TMPA"
  fi

  # Ensure the default block exists (but add only once)
  ensure_default_block "$TMPA"

  # -------------------------- Set git signing key if requested ------------------
  if [ "$SET_GIT_SIGNING_KEY" -eq 1 ]; then
    # Extract public key string (ONEP_PUB) and format for git config
    # Only works for ed25519/rsa keys in OpenSSH format
    if [ -z "$ONEP_PUB" ] && [ -s "$PUB_FILE" ]; then
      ONEP_PUB="$(cat "$PUB_FILE" | head -n1)"
    fi
    if [ -n "$ONEP_PUB" ]; then
      # Extract the public key string (e.g., ssh-ed25519 AAAA... user@host)
      GIT_SIGNING_KEY="$(echo "$ONEP_PUB" | awk '{print $2}')"
      # Get current git signing key (global)
      CURRENT_GIT_SIGNING_KEY="$(git config --global --get user.signingkey || true)"
      # Set gpg.format=ssh if not already
      CURRENT_GPG_FORMAT="$(git config --global --get gpg.format || true)"
      if [ "$CURRENT_GPG_FORMAT" != "ssh" ]; then
        git config --global gpg.format ssh
        echo "Set git global gpg.format=ssh"
      fi
      if [ "$CURRENT_GIT_SIGNING_KEY" != "$GIT_SIGNING_KEY" ]; then
        git config --global user.signingkey "$GIT_SIGNING_KEY"
        echo "Set git global user.signingkey to match SSH key ($GIT_SIGNING_KEY)"
      else
        echo "Git global user.signingkey already matches this SSH key."
      fi
    else
      echo "Warning: Could not determine SSH public key for git signing key update." >&2
    fi
  fi

  # Main host block
  render_host_block "$HOST" "$HOSTNAME" "$USER_NAME" "$PUB_FILE" ""
  upsert_host_block "$TMPA" "$TMPB" "$HOST"
  mv "$TMPB" "$TMPA"

  # Optional IPv4 alias block
  if [ "$AUTO_ALIAS" -eq 1 ] && [ -n "$HOST_IPV4" ] && [ "$HOST_IPV4" != "$HOST" ]; then
    # Create a single block with both hostname and IP as aliases
    render_host_block "$HOST" "$HOSTNAME" "$USER_NAME" "$PUB_FILE" "$HOST $HOST_IPV4"
    upsert_host_block "$TMPA" "$TMPB" "$HOST"
    mv "$TMPB" "$TMPA"
  else
  render_host_block "$HOST" "$HOSTNAME" "$USER_NAME" "$PUB_FILE" ""
  upsert_host_block "$TMPA" "$TMPB" "$HOST"
  mv "$TMPB" "$TMPA"
  fi

  # -------------------------- Output / write ------------------------------------
  if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "----- DRY RUN: would write $CONF_FILE -----"
    cat "$TMPA"
    echo "----------------------------------------------"
  else
    # Backup existing config before overwrite
    if [ -s "$CONF_FILE" ]; then
      cp -p "$CONF_FILE" "$CONF_FILE.bak.$(date +%Y%m%d%H%M%S)"
    fi
    install -m 600 "$TMPA" "$CONF_FILE"
    echo "Updated $CONF_FILE"
  fi

  # Ensure ~/.ssh exists with correct permissions before final install (no-op if already done)
  if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi

  # Show summary (fingerprint if available)
  FP_DISPLAY=""
  if [ -s "$PUB_FILE" ]; then
    FP_DISPLAY="$(fp_from_file "$PUB_FILE" || true)"
  fi

  echo
  echo "Host:        $HOST"
  echo "HostName:    $HOSTNAME"
  echo "User:        $USER_NAME"
  echo "IdentityFile $PUB_FILE"
  [ -n "$FP_DISPLAY" ] && echo "Fingerprint: $FP_DISPLAY"
  [ "$DRY_RUN" -eq 1 ] && echo "Done (dry-run)." || echo "Done."

fi # End of main execution (OPSSH_TEST_MODE check)
