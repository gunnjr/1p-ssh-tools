# 1Password SSH Tools

Helper scripts for managing SSH keys using the [1Password CLI](https://developer.1password.com/docs/cli/).  
These scripts make it easier to create, view, and manage SSH keys stored in 1Password — including optional integration with the 1Password SSH agent (`agent.toml`).

---

## 🧰 Included Tools

### `op-gen-ssh-pubonly.sh`
Creates or reuses SSH keys directly in 1Password, and (optionally) updates your local 1Password SSH Agent configuration file.

**Capabilities:**
- Searches for existing SSH key records by host and user.
- Creates new keys in 1Password if none are found.
- Copies the public key to clipboard for manual installation on the target host.
- (Optionally) inserts or updates the key in your `~/.config/1Password/ssh/agent.toml`.

---

### `op-show-ssh-pub.sh`
Displays existing SSH keys stored in 1Password — including their public keys — and copies the selected public key to the clipboard.

**Useful for:**
- Quickly retrieving keys to add to remote hosts.
- Verifying which SSH keys are already stored in 1Password.

---

## 🧭 Installation

1. Clone this repository:
   ```bash
   git clone git@github.com:gunnjr/1p-ssh-tools.git
   cd 1p-ssh-tools
   ```

2. Make scripts executable:
   ```bash
   chmod +x op-*.sh
   ```

3. Move them somewhere on your `$PATH`, such as:
   ```bash
   mv op-*.sh ~/bin/
   ```

---

## 🧪 Usage

### Generate or Reuse a Key
```bash
op-gen-ssh-pubonly.sh --host example.com --user myuser
```

If a key already exists, you’ll be prompted to reuse it or create a new one.  
When reusing, the public key will be displayed and copied to the clipboard.

### View a Stored Key
```bash
op-show-ssh-pub.sh example.com
```

Lists all matching keys and displays the selected one’s public key.

---

## ⚙️ 1Password SSH Agent Integration

If you use the 1Password SSH Agent, your configuration file should live here:

```
~/.config/1Password/ssh/agent.toml
```

Each SSH key you want the agent to load should have an entry like this:

```toml
[[ssh-keys]]
item = "SSH Key - example.com - myuser"
vault = "Private"
```

> **Note:**  
> The `allowed-hosts` directive is **not currently supported** by the 1Password SSH Agent and should not be used.

---

## 💬 Disclaimer & Acknowledgement

> ⚠️ **Important Note from John Gunn**  
> I’m just a weekend hacker who enjoys automating things.  
> These scripts were created **with extensive help from ChatGPT** and reflect a collaborative learning process more than a polished product.  
>
> Please treat them as such: they work for me, and they might work for you — but you use them at your own risk.  
>
> I **welcome constructive feedback and contributions**, but please keep it respectful — especially regarding my reliance on ChatGPT.  
> You get what you get. 🙂

---

## 🧾 License

MIT License — see [`LICENSE`](LICENSE) for details.

---

## 🙌 Acknowledgments

- [1Password Developer Docs](https://developer.1password.com/docs/ssh/)
- [OpenSSH](https://www.openssh.com/)
- And, of course, ChatGPT — for code scaffolding, debugging, and keeping the process fun.
