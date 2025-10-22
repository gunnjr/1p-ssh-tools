# 1Password SSH Tools

A lightweight toolkit to integrate **1Password SSH Agent** with local SSH configuration on macOS and Linux.  
These tools automate key creation, publication, and configuration file management for a seamless `ssh` workflow.

---

## 🚀 Overview

This repository contains helper scripts designed to simplify managing SSH keys stored in **1Password**.

| Script | Description |
|---------|--------------|
| `scripts/op-ssh-keygen.sh` | Generates or retrieves SSH key pairs in 1Password and exports public keys locally. |
| `scripts/op-ssh-status.sh` | Displays local SSH configuration, key fingerprints, and 1Password matches. |
| `scripts/op-ssh-show-pubkey.sh` | Quickly retrieves and displays public keys stored in 1Password. |
| `scripts/op-ssh-addhost.sh` *(coming soon)* | Creates or reuses 1Password SSH keys, validates local public keys, and updates your SSH config file. |

All scripts are written for **macOS’s native Bash 3.2** for maximum portability.

---

## 🧩 Script Summaries

### 🔑 `op-ssh-keygen.sh`

- Searches for an existing SSH key in 1Password (by host or title pattern).  
- If not found, creates a new Ed25519 key in 1Password.  
- Exports the public key to a local `.pub` file under `~/.ssh`.  
- Copies the key to clipboard for convenience.  
- Optionally updates 1Password’s agent configuration (future enhancement).

### 🧾 `op-ssh-status.sh`

- Lists configured SSH hosts and corresponding local/public key files.  
- Verifies if local key fingerprints match 1Password records.  
- Detects missing or mismatched configuration and suggests fixes.  
- Automatically signs into 1Password CLI if required.  
- Output is formatted for readability in terminal tables.

### 🧷 `op-ssh-show-pubkey.sh`

- Simple utility to retrieve, display, and copy public keys from 1Password.  
- Useful for quickly deploying keys to remote servers (e.g., `authorized_keys`).

### 🧱 `op-ssh-addhost.sh` *(under development)*

Planned functionality:

- Checks for an existing SSH key in 1Password (creates one if missing).  
- Validates or generates a matching local `.pub` file.  
- Confirms the key pair matches between local and 1Password.  
- Updates your SSH config with the proper `Host`, `IdentityFile`, and `IdentitiesOnly yes`.  
- Optionally resolves local hostnames to IPs and creates alias blocks.  
- Supports `--dry-run`, `--yes`, and `--auto-alias` modes.

---

## ⚙️ Requirements

- **macOS or Linux**
- **1Password CLI v2+**
- **jq** — command-line JSON processor  
- **ssh-keygen** — typically part of OpenSSH  
- **Bash 3.2+ (macOS default)**

Optional (for full compatibility testing):

- `dig` or `ping` for hostname resolution

To verify dependencies:

```bash
for cmd in op jq ssh-keygen; do command -v $cmd >/dev/null || echo "Missing: $cmd"; done
```

---

## 🧰 Installation

Clone this repo and install the scripts into your `~/bin` directory:

```bash
git clone https://github.com/gunnjr/1p-ssh-tools.git ~/OneDrive/dev/1p-ssh-tools
cd ~/OneDrive/dev/1p-ssh-tools
mkdir -p ~/bin
cp scripts/*.sh ~/bin/
chmod +x ~/bin/op-ssh-*.sh
```

Ensure your shell’s PATH includes `~/bin`:

```bash
export PATH="$HOME/bin:$PATH"
```

---

## 🧩 Example Workflow

```bash
# Generate or reuse an SSH key in 1Password and save public key locally
scripts/op-ssh-keygen.sh --host github.com --user git

# Add a host to SSH config using an existing key
scripts/op-ssh-addhost.sh --host github.com --user git --pub-file ~/.ssh/github_ed25519.pub

# Verify all SSH host/key configurations
scripts/op-ssh-status.sh --all

# Display public key for deployment
scripts/op-ssh-show-pubkey.sh github.com
```

---

## 🔒 Security Notes

- All scripts interact **only** with your local 1Password CLI session.  
- No secrets are logged, stored, or transmitted externally.  
- When in doubt, run scripts in `--dry-run` mode to preview behavior.

---

## 🧠 Roadmap

| Version | Milestone | Description |
|----------|------------|-------------|
| `v0.4-docs` | Documentation Refresh | Updated README, new structure, new naming convention |
| `v0.5-addhost` | AddHost Integration | Full implementation of `op-ssh-addhost.sh` |
| `v0.6-bootstrap` | Bootstrap Integration | Auto-deploy scripts to `~/bin` and integrate into bootstrap process |

---

## 💬 Disclaimer

> I'm a weekend hacker — these tools were created and refined with heavy help from ChatGPT.  
> They work great for me, but **you get what you get**.  
> Constructive feedback and contributions are always welcome.  
> Just please, no snarking about AI-assisted development. 😉

---

## 📜 License

MIT License © 2025 [John Gunn](https://github.com/gunnjr)
