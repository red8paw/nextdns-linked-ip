# nextdns-update

A macOS daemon that periodically updates your [NextDNS](https://nextdns.io) linked IP address. It runs in the background via launchd and optionally filters by router MAC address — so updates only happen when you're on a specific network.

---

## How it works

NextDNS's [Linked IP](https://my.nextdns.io) feature pins your dynamic public IP to your configuration. This script calls your personal NextDNS linked-IP URL on a schedule to keep it current, which is useful if your ISP changes your IP regularly.

---

## Requirements

- macOS (tested on Sonoma 14+)
- zsh (pre-installed on macOS)
- curl (pre-installed on macOS)

---

## Get your router's MAC address

The MAC filter identifies your home (or office) network by the router's hardware address. This works without any Location Services permission.

Run this command in your terminal:

```zsh
arp -n "$(route -n get default | awk '/gateway:/{print $2}')" | awk '{print $4}'
```

Example output:

```
a4:39:b3:d8:73:90
```

Save this value — you'll pass it to the installer with `--macs`.

To find MAC addresses for multiple networks, connect to each one and run the command above.

---

## Installation

### 1. Clone the repo

```zsh
git clone https://github.com/yourname/nextdns-update.git
cd nextdns-update
```

### 2. Get your NextDNS linked-IP URL

Open [my.nextdns.io](https://my.nextdns.io), go to your configuration → **Linked IP** → copy the URL. It looks like:

```
https://link-ip.nextdns.io/abc123/xxxxxxxxxxxx
```

### 3. Run the installer

```zsh
chmod +x install.sh
./install.sh --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN"
```

With a router MAC filter (recommended):

```zsh
./install.sh \
  --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN" \
  --macs "a4:39:b3:d8:73:90"
```

Multiple networks (comma-separated, no spaces):

```zsh
./install.sh \
  --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN" \
  --macs "a4:39:b3:d8:73:90,11:22:33:44:55:66"
```

The installer will:
- Copy the script to `~/.local/bin/nextdns-update.sh`
- Generate a launchd plist at `~/Library/LaunchAgents/com.user.nextdns-update.plist`
- Load the agent so it starts immediately and on every login

### 4. Uninstall

```zsh
./install.sh --uninstall
```

---

## Installer options

| Option | Description | Default |
|---|---|---|
| `-u`, `--url` | NextDNS linked-IP URL **(required)** | — |
| `-i`, `--interval` | Update interval in seconds | `300` (5 min) |
| `-m`, `--macs` | Comma-separated router MAC allowlist | disabled |
| `-v`, `--verbose` | Enable verbose logging in the daemon | off |
| `--uninstall` | Remove the agent and all installed files | — |

---

## Manual script usage

You can also run the script directly without installing it.

```zsh
./nextdns-update.sh --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN"
```

Run once and exit:

```zsh
./nextdns-update.sh --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN" --once
```

With MAC filter and custom interval:

```zsh
./nextdns-update.sh \
  --url "https://link-ip.nextdns.io/YOUR_ID/YOUR_TOKEN" \
  --macs "a4:39:b3:d8:73:90" \
  --interval 60
```

### Script options

| Option | Description | Default |
|---|---|---|
| `-u`, `--url` | NextDNS linked-IP URL **(required)** | — |
| `-i`, `--interval` | Update interval in seconds | `300` |
| `-m`, `--macs` | Comma-separated router MAC allowlist | disabled |
| `-o`, `--once` | Run once and exit | off |
| `-v`, `--verbose` | Verbose debug output | off |
| `-h`, `--help` | Show help | — |

---

## Logs

Logs are written to `~/Library/Logs/nextdns-update/`:

```zsh
tail -f ~/Library/Logs/nextdns-update/nextdns-update.log
tail -f ~/Library/Logs/nextdns-update/nextdns-update.error.log
```

---

## MAC filter behaviour

| Situation | Behaviour |
|---|---|
| No `--macs` specified | Always updates, on any network |
| `--macs` specified, router MAC matches | Updates normally |
| `--macs` specified, router MAC does not match | Skips update, logs a message |
| Not connected to any network | Skips update, logs a warning |

MAC comparison is case-insensitive (`A4:39:B3:...` matches `a4:39:b3:...`).
