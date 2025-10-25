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
| `scripts/op-ssh-addhost.sh` | Adds or updates SSH Host entries in your config using a 1Password-managed SSH key, ensuring key consistency and supporting advanced options. |

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

### 🧱 `op-ssh-addhost.sh`

Adds or updates a Host entry in your `~/.ssh/config` using a 1Password-managed SSH key. Ensures your SSH configuration and public key files are consistent with 1Password, and supports advanced automation and safety features.

**Key features:**

- Ensures you are signed into the 1Password CLI.
- Finds or creates a 1Password SSH key item (`SSH Key - <host> - <user>`).
- Retrieves the public key from 1Password and writes or validates the local `.pub` file.
- If the local `.pub` file exists but does not match 1Password, prompts to back up and overwrite (or does so automatically with `--force`/`--yes`).
- Upserts a `Host` block in your SSH config, setting `HostName`, `User`, `IdentityFile`, and `IdentitiesOnly yes`.
- Optionally adds an alias block for the host's IPv4 address (`--auto-alias`).
- Supports `--dry-run` (preview changes), `--yes` (non-interactive), `--force` (overwrite mismatches), and custom SSH directory or config locations.
- Optionally sets your global git commit signing key to match this SSH key (`--set-git-signing-key`).
- macOS and Linux compatible; no Bash 4+ features required.

**Example usage:**

```bash
# Add or update a host entry using a 1Password-managed key
scripts/op-ssh-addhost.sh --host github.com --user git

# Add with a specific public key file and auto-alias for IPv4
scripts/op-ssh-addhost.sh --host myserver.local --user admin --auto-alias --pub-file ~/.ssh/myserver_ed25519.pub

# Preview changes without writing files
scripts/op-ssh-addhost.sh --host github.com --user git --dry-run
```

Run with `-h` or `--help` for all options and details.

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

## 🧪 Tests

Automated and helper tests are provided for all major scripts. See [tests/README.md](tests/README.md) for details on test structure, dependencies, and how to run both Bats and Bash-based tests.

## 🧹 Linting

Shell script linting is provided by [`scripts/lint.sh`](scripts/lint.sh), which runs `shellcheck` (and optionally `shfmt`) on all scripts. See [docs/linting.md](docs/linting.md) for usage and setup instructions.

All contributors are encouraged to lint their code before submitting changes.

## 🗒️ Release History

| Version | Date         | Notes                                                      |
|---------|--------------|------------------------------------------------------------|
| 1.0.1   | 2025-10-24   | Documentation and README improvements, test/lint docs added |
| 1.0.0   | 2025-10-??   | Initial stable release: all core scripts and test suite     |

---

## 💬 Disclaimer

> I'm a weekend hacker — these tools were created and refined with heavy help from ChatGPT.  
> They work great for me, but **you get what you get**.  
> Constructive feedback and contributions are always welcome.  
> Just please, no snarking about AI-assisted development. 😉

---

## 📜 License

MIT License © 2025 [John Gunn](https://github.com/gunnjr)
