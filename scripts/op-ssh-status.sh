#!/usr/bin/env bash
set -euo pipefail
#
# op-ssh-status.sh — Audit SSH hosts, local public keys, and 1Password SSH keys.
# macOS Bash 3.2 compatible (no mapfile, no assoc arrays).
#
# Now buffers the table to a temp file so stderr messages appear first,
# followed by a clean uninterrupted table at the end.
#
# Usage:
#   op-ssh-status.sh --all
#   op-ssh-status.sh --host <alias_or_regex>
#   op-ssh-status.sh --orphans
#   op-ssh-status.sh --keys-only | --pubs-only | --config-only
#   op-ssh-status.sh --all --json   # JSON mode (no temp buffering)
#
# Exits:
#   0: all good; 1: warnings; 2+: operational error

SSH_DIR="${HOME}/.ssh"
CONF_FILE="${SSH_DIR}/config"

need() { command -v "$1" > /dev/null 2>&1 || {
  echo "Missing dependency: $1" >&2
  exit 2
}; }
need jq
need ssh-keygen

ensure_op_signed_in() {
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

HAS_OP=0
ensure_op_signed_in

HOST_PATTERN=""
MODE="default"
OUT_JSON=0

usage() {
  cat << 'TXT'
op-ssh-status.sh — Audit SSH hosts, public keys, and 1Password SSH keys

Usage:
  op-ssh-status.sh --all
  op-ssh-status.sh --host <alias_or_regex>
  op-ssh-status.sh --orphans
  op-ssh-status.sh --keys-only | --pubs-only | --config-only
  op-ssh-status.sh --all --json
TXT
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    --host)
      HOST_PATTERN="${2:-}"
      MODE="host"
      shift 2
      ;;
    --orphans)
      MODE="orphans"
      shift
      ;;
    --json)
      OUT_JSON=1
      shift
      ;;
    --keys-only)
      MODE="keys"
      shift
      ;;
    --pubs-only)
      MODE="pubs"
      shift
      ;;
    --config-only)
      MODE="config"
      shift
      ;;
    -h | --help) usage ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      ;;
  esac
done

# ---------- discover .pub files ----------
PUB_PATHS=()
PUB_FPRS=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  fp="$(ssh-keygen -lf "$p" 2> /dev/null | awk '{print $2}')" || true
  [ -n "${fp:-}" ] || fp="INVALID"
  PUB_PATHS+=("$p")
  PUB_FPRS+=("$fp")
done < <({ find "$SSH_DIR" -maxdepth 1 -type f -name "*.pub" 2> /dev/null || true; } | sort)

# ---------- 1Password SSH keys (optional) ----------
OP_IDS=()
OP_TITLES=()
OP_FPRS=()
if [ "$HAS_OP" -eq 1 ]; then
  items_json="$(op item list --categories 'SSH Key' --format json 2> /dev/null || true)"
  : "${items_json:='[]'}"
  count="$(printf '%s\n' "$items_json" | jq 'length' 2> /dev/null || echo 0)"
  i=0
  while [ $i -lt "$count" ]; do
    id="$(printf '%s\n' "$items_json" | jq -r ".[$i].id")"
    title="$(printf '%s\n' "$items_json" | jq -r ".[$i].title")"
    item_json="$(op item get "$id" --format json 2> /dev/null || echo '{}')"
    pub="$(printf '%s\n' "$item_json" | jq -r '
      (.fields[]? | select((.label // .t // "")|ascii_downcase=="public key") | (.value // .v)) //
      (.sections[]?.fields[]? | select(.t=="public key") | .v) // empty
    ')"
    fp=""
    if [ -n "${pub:-}" ] && [ "$pub" != "null" ]; then
      fp="$(printf '%s\n' "$pub" | ssh-keygen -lf /dev/stdin 2> /dev/null | awk '{print $2}')"
    fi
    OP_IDS+=("$id")
    OP_TITLES+=("$title")
    OP_FPRS+=("${fp:-}")
    i=$((i + 1))
  done
fi

find_1p_title_by_fp() {
  _fp="$1"
  j=0
  while [ $j -lt ${#OP_FPRS[@]} ]; do
    if [ -n "$_fp" ] && [ "${OP_FPRS[$j]}" = "$_fp" ]; then
      echo "${OP_TITLES[$j]}"
      return 0
    fi
    j=$((j + 1))
  done
  return 1
}
find_fp_by_path() {
  _p="$1"
  j=0
  while [ $j -lt ${#PUB_PATHS[@]} ]; do
    if [ "${PUB_PATHS[$j]}" = "$_p" ]; then
      echo "${PUB_FPRS[$j]}"
      return 0
    fi
    j=$((j + 1))
  done
  return 1
}

# ---------- parse ~/.ssh/config ----------
ALIASES=()
HNAMES=()
USERS=()
IDFILES=()
if [ -f "$CONF_FILE" ]; then
  block=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      [Hh][Oo][Ss][Tt]*)
        if [ -n "$block" ]; then
          host_line="$(printf '%s\n' "$block" | grep -iE '^Host[[:space:]]+' | head -n1 || true)"
          if [ -n "$host_line" ]; then
            names="$(printf '%s\n' "$host_line" | sed -E 's/^[Hh]ost[[:space:]]+//')"
            hname="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*HostName[[:space:]]/{print $2}' | tail -n1)"
            uuser="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*User[[:space:]]/{print $2}' | tail -n1)"
            idf="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*IdentityFile[[:space:]]/{sub(/^[[:space:]]*IdentityFile[[:space:]]+/,"");print}' | tail -n1)"

            set -f # disable globbing so "Host *" doesn't expand into filenames
            for a in $names; do
              ALIASES+=("$a")
              HNAMES+=("${hname:-}")
              USERS+=("${uuser:-}")
              IDFILES+=("${idf:-}")
            done
            set +f # re-enable globbing

          fi
        fi
        block="$line"$'\n'
        ;;
      *) block="$block$line"$'\n' ;;
    esac
  done < "$CONF_FILE"

  if [ -n "$block" ]; then
    host_line="$(printf '%s\n' "$block" | grep -iE '^Host[[:space:]]+' | head -n1 || true)"
    if [ -n "$host_line" ]; then
      names="$(printf '%s\n' "$host_line" | sed -E 's/^[Hh]ost[[:space:]]+//')"
      hname="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*HostName[[:space:]]/{print $2}' | tail -n1)"
      uuser="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*User[[:space:]]/{print $2}' | tail -n1)"
      idf="$(printf '%s\n' "$block" | awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*IdentityFile[[:space:]]/{sub(/^[[:space:]]*IdentityFile[[:space:]]+/,"");print}' | tail -n1)"

      set -f
      for a in $names; do
        ALIASES+=("$a")
        HNAMES+=("${hname:-}")
        USERS+=("${uuser:-}")
        IDFILES+=("${idf:-}")
      done
      set +f

    fi
  fi
fi

# Filter by --host pattern if set
if [ "$MODE" = "host" ]; then
  [ -n "${HOST_PATTERN:-}" ] || {
    echo "Missing --host <pattern>" >&2
    exit 2
  }
  _A=() _H=() _U=() _I=()
  i=0
  while [ $i -lt ${#ALIASES[@]} ]; do
    a="${ALIASES[$i]}"
    echo "$a" | grep -E "$HOST_PATTERN" > /dev/null 2>&1 || {
      i=$((i + 1))
      continue
    }
    _A+=("$a")
    _H+=("${HNAMES[$i]}")
    _U+=("${USERS[$i]}")
    _I+=("${IDFILES[$i]}")
    i=$((i + 1))
  done
  ALIASES=("${_A[@]}")
  HNAMES=("${_H[@]}")
  USERS=("${_U[@]}")
  IDFILES=("${_I[@]}")
fi

# ---------- temp file for table buffering ----------
# In JSON mode we print directly; otherwise buffer table to temp so stderr shows first.
TABLE_TMP=""
if [ "$OUT_JSON" -eq 0 ]; then
  TABLE_TMP="/tmp/op-ssh-status.$$"
  : > "$TABLE_TMP"
  trap 'rm -f "$TABLE_TMP"' EXIT
fi

# ---------- modes ----------
if [ "$MODE" = "keys" ]; then
  if [ "$HAS_OP" -eq 0 ] || [ ${#OP_IDS[@]} -eq 0 ]; then
    echo "No 1Password SSH keys found or not signed in." >&2
    exit 1
  fi
  if [ "$OUT_JSON" -eq 1 ]; then
    printf "["
    j=0
    first=1
    while [ $j -lt ${#OP_TITLES[@]} ]; do
      [ $first -eq 0 ] && printf ","
      printf '{"title":%s,"fingerprint":%s}' \
        "$(printf '%s' "${OP_TITLES[$j]}" | jq -R '.') " \
        "$(printf '%s' "${OP_FPRS[$j]}" | jq -R '.') "
      first=0
      j=$((j + 1))
    done
    printf "]\n"
    exit 0
  else
    printf "%-50s  %s\n" "1P_TITLE" "FINGERPRINT" >> "$TABLE_TMP"
    printf "%s\n" "-------------------------------------------------------------------------" >> "$TABLE_TMP"
    j=0
    while [ $j -lt ${#OP_TITLES[@]} ]; do
      printf "%-50s  %s\n" "${OP_TITLES[$j]}" "${OP_FPRS[$j]}" >> "$TABLE_TMP"
      j=$((j + 1))
    done
    echo
    cat "$TABLE_TMP"
    exit 0
  fi
fi

if [ "$MODE" = "pubs" ]; then
  if [ "$OUT_JSON" -eq 1 ]; then
    printf "["
    j=0
    first=1
    while [ $j -lt ${#PUB_PATHS[@]} ]; do
      [ $first -eq 0 ] && printf ","
      printf '{"path":%s,"fingerprint":%s}' \
        "$(printf '%s' "${PUB_PATHS[$j]}" | jq -R '.')" \
        "$(printf '%s' "${PUB_FPRS[$j]}" | jq -R '.')"
      first=0
      j=$((j + 1))
    done
    printf "]\n"
    exit 0
  else
    printf "%-45s  %s\n" "PUB_PATH" "FINGERPRINT" >> "$TABLE_TMP"
    printf "%s\n" "----------------------------------------------------------------" >> "$TABLE_TMP"
    j=0
    while [ $j -lt ${#PUB_PATHS[@]} ]; do
      printf "%-45s  %s\n" "${PUB_PATHS[$j]}" "${PUB_FPRS[$j]}" >> "$TABLE_TMP"
      j=$((j + 1))
    done
    echo
    cat "$TABLE_TMP"
    exit 0
  fi
fi

if [ "$MODE" = "config" ] || [ "$MODE" = "all" ] || [ "$MODE" = "default" ] || [ "$MODE" = "host" ]; then
  WARN=0
  if [ "$OUT_JSON" -eq 1 ]; then
    printf "["
  else
    printf "%-22s %-18s %-10s %-34s %-44s %-30s %-s\n" \
      "HOST" "HOSTNAME" "USER" "IDENTITYFILE" "FINGERPRINT" "1P_KEY" "STATUS" >> "$TABLE_TMP"
    printf '%*s\n' 170 '' | tr ' ' '-' >> "$TABLE_TMP"
    if [ ${#ALIASES[@]} -eq 0 ]; then
      echo "No Host entries found in $CONF_FILE" >&2
      echo
      cat "$TABLE_TMP"
      exit 1
    fi
  fi

  i=0
  first=1
  while [ $i -lt ${#ALIASES[@]} ]; do
    alias="${ALIASES[$i]}"
    hname="${HNAMES[$i]}"
    user="${USERS[$i]}"
    idf="${IDFILES[$i]}"

    st="OK"
    tip=""
    fp=""
    onep=""

    if [ -z "${idf:-}" ]; then
      st="WARN: no IdentityFile"
      tip="Use op-ssh-addhost.sh to set IdentityFile and IdentitiesOnly."
      WARN=1
    else
      if [ ! -f "$idf" ]; then
        st="WARN: missing .pub"
        tip="Expected $idf. Re-run op-ssh-addhost.sh or recreate public key."
        WARN=1
      else
        fp="$(find_fp_by_path "$idf" || true)"
        if [ -z "${fp:-}" ] || [ "$fp" = "INVALID" ]; then
          st="WARN: unreadable .pub"
          tip="Check permissions or regenerate."
          WARN=1
        else
          if [ "$HAS_OP" -eq 1 ]; then
            onep="$(find_1p_title_by_fp "$fp" || true)"
            if [ -z "${onep:-}" ]; then
              st="WARN: no matching 1P key"
              tip="Ensure 1Password has the private key for this pub key."
              WARN=1
            fi
          else
            st="INFO: op not signed in"
            tip="Run: op signin (to verify 1P match)"
            WARN=1
          fi
        fi
      fi
    fi

    if [ "$OUT_JSON" -eq 1 ]; then
      [ $first -eq 0 ] && printf ","
      printf '{"alias":%s,"hostName":%s,"user":%s,"identityFile":%s,"fingerprint":%s,"onepassword":%s,"status":%s,"tip":%s}' \
        "$(printf '%s' "$alias" | jq -R '.')" \
        "$(printf '%s' "$hname" | jq -R '.')" \
        "$(printf '%s' "$user" | jq -R '.')" \
        "$(printf '%s' "$idf" | jq -R '.')" \
        "$(printf '%s' "$fp" | jq -R '.')" \
        "$(printf '%s' "$onep" | jq -R '.')" \
        "$(printf '%s' "$st" | jq -R '.')" \
        "$(printf '%s' "$tip" | jq -R '.')"
      first=0
    else
      printf "%-22s %-18s %-10s %-34s %-44s %-30s %-s\n" \
        "$alias" "$hname" "$user" "$idf" "$fp" "$onep" "$st" >> "$TABLE_TMP"
      if [ -n "$tip" ]; then
        # keep helper on stderr so it prints before the table
        echo "- $alias: $tip" >&2
      fi
    fi

    i=$((i + 1))
  done

  if [ "$OUT_JSON" -eq 1 ]; then
    printf "]\n"
  else
    echo
    cat "$TABLE_TMP"
  fi

  [ $WARN -eq 0 ] && exit 0 || exit 1
fi

if [ "$MODE" = "orphans" ]; then
  USED=()
  i=0
  while [ $i -lt ${#IDFILES[@]} ]; do
    p="${IDFILES[$i]}"
    [ -n "$p" ] && USED+=("$p")
    i=$((i + 1))
  done

  if [ "$OUT_JSON" -eq 1 ]; then
    printf "["
    j=0
    first=1
    while [ $j -lt ${#PUB_PATHS[@]} ]; do
      p="${PUB_PATHS[$j]}"
      fp="${PUB_FPRS[$j]}"
      inuse=0
      k=0
      while [ $k -lt ${#USED[@]} ]; do
        [ "${USED[$k]}" = "$p" ] && {
          inuse=1
          break
        }
        k=$((k + 1))
      done
      if [ $inuse -eq 0 ]; then
        [ $first -eq 0 ] && printf ","
        printf '{"path":%s,"fingerprint":%s}' \
          "$(printf '%s' "$p" | jq -R '.')" \
          "$(printf '%s' "$fp" | jq -R '.')"
        first=0
      fi
      j=$((j + 1))
    done
    printf "]\n"
    exit 0
  else
    [ -n "${TABLE_TMP:-}" ] || {
      echo "Internal error: TABLE_TMP missing" >&2
      exit 2
    }
    printf "%-45s  %s\n" "ORPHAN_PUB" "FINGERPRINT" >> "$TABLE_TMP"
    printf "%s\n" "----------------------------------------------------------------" >> "$TABLE_TMP"
    printed=0
    j=0
    while [ $j -lt ${#PUB_PATHS[@]} ]; do
      p="${PUB_PATHS[$j]}"
      fp="${PUB_FPRS[$j]}"
      inuse=0
      k=0
      while [ $k -lt ${#USED[@]} ]; do
        [ "${USED[$k]}" = "$p" ] && {
          inuse=1
          break
        }
        k=$((k + 1))
      done
      if [ $inuse -eq 0 ]; then
        printf "%-45s  %s\n" "$p" "$fp" >> "$TABLE_TMP"
        printed=1
      fi
      j=$((j + 1))
    done
    echo
    cat "$TABLE_TMP"
    [ $printed -eq 1 ] || echo "No orphaned .pub files."
    exit 0
  fi
fi

usage
