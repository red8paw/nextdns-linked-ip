#!/usr/bin/env zsh
# install.sh — Install the NextDNS IP updater as a launchd user agent
#
# Usage:
#   ./install.sh -u <url> [options]
#
# Options:
#   -u, --url <url>          NextDNS linked-IP URL        (required)
#                            e.g. https://link-ip.nextdns.io/{id}/{token}
#   -i, --interval <secs>    Polling interval             (default: 300)
#   -m, --macs <mac,...>     Comma-separated router MAC list (optional)
#   -v, --verbose            Enable verbose logging in the daemon
#       --uninstall          Remove the agent and its files
#   -h, --help               Show this message

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="nextdns-update.sh"
PLIST_NAME="com.user.nextdns-update.plist"
PLIST_TEMPLATE="${SCRIPT_DIR}/${PLIST_NAME}"

INSTALL_DIR="${HOME}/.local/bin"
LOG_DIR="${HOME}/Library/Logs/nextdns-update"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
INSTALLED_SCRIPT="${INSTALL_DIR}/${SCRIPT_NAME}"
INSTALLED_PLIST="${LAUNCH_AGENTS_DIR}/${PLIST_NAME}"

# ── Defaults ──────────────────────────────────────────────────────────────────
NEXTDNS_URL=""
NEXTDNS_ID=""
NEXTDNS_TOKEN=""
INTERVAL=300
ALLOWED_MACS=""
VERBOSE=false
UNINSTALL=false

# ── Helpers ───────────────────────────────────────────────────────────────────
info()  { echo "  [✓] $*"; }
step()  { echo "\n  ──  $*"; }
warn()  { echo "  [!] $*" >&2; }
die()   { echo "\n  [✗] ERROR: $*\n" >&2; exit 1; }

usage() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
  exit 0
}

# ── URL parsing ───────────────────────────────────────────────────────────────
parse_nextdns_url() {
  local url="$1"
  if [[ "$url" =~ ^https://link-ip\.nextdns\.io/([^/]+)/([^/]+)$ ]]; then
    NEXTDNS_URL="$url"
    NEXTDNS_ID="${match[1]}"
    NEXTDNS_TOKEN="${match[2]}"
  else
    die "Invalid NextDNS URL: '$url'\n       Expected format: https://link-ip.nextdns.io/{id}/{token}"
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--url)      parse_nextdns_url "$2"; shift 2 ;;
      -i|--interval) INTERVAL="$2";          shift 2 ;;
      -m|--macs)     ALLOWED_MACS="$2";      shift 2 ;;
      -v|--verbose)  VERBOSE=true;            shift ;;
      --uninstall)   UNINSTALL=true;          shift ;;
      -h|--help)     usage ;;
      *) die "Unknown option: $1. Use -h for help." ;;
    esac
  done
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
do_uninstall() {
  step "Uninstalling NextDNS IP updater..."

  if [[ -f "$INSTALLED_PLIST" ]]; then
    launchctl unload "$INSTALLED_PLIST" 2>/dev/null || true
    rm -f "$INSTALLED_PLIST"
    info "Removed launchd plist."
  else
    warn "Plist not found — skipping unload."
  fi

  if [[ -f "$INSTALLED_SCRIPT" ]]; then
    rm -f "$INSTALLED_SCRIPT"
    info "Removed script."
  fi

  echo "\n  Done. Log files (if any) remain in: $LOG_DIR"
  echo "  Remove them manually with: rm -rf '$LOG_DIR'\n"
  exit 0
}

# ── Validation ────────────────────────────────────────────────────────────────
validate() {
  [[ -n "$NEXTDNS_URL" ]] || die "NextDNS URL is required (-u/--url).\n       e.g. https://link-ip.nextdns.io/{id}/{token}"

  if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
    die "Interval must be a positive integer."
  fi

  [[ -f "${SCRIPT_DIR}/${SCRIPT_NAME}" ]] \
    || die "Cannot find '${SCRIPT_NAME}' in the same directory as install.sh."

  [[ -f "$PLIST_TEMPLATE" ]] \
    || die "Cannot find '${PLIST_NAME}' in the same directory as install.sh."
}

# ── Build ProgramArguments XML ────────────────────────────────────────────────
build_program_arguments() {
  local args=(
    "    <string>${INSTALLED_SCRIPT}</string>"
    "    <string>--url</string>"
    "    <string>${NEXTDNS_URL}</string>"
    "    <string>--interval</string>"
    "    <string>${INTERVAL}</string>"
  )

  if [[ -n "$ALLOWED_MACS" ]]; then
    args+=(
      "    <string>--macs</string>"
      "    <string>${ALLOWED_MACS}</string>"
    )
  fi

  $VERBOSE && args+=("    <string>--verbose</string>")

  printf '%s\n' "${args[@]}"
}

# ── Install ───────────────────────────────────────────────────────────────────
do_install() {
  validate

  step "Creating directories..."
  mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
  info "Install dir : $INSTALL_DIR"
  info "Log dir     : $LOG_DIR"
  info "LaunchAgents: $LAUNCH_AGENTS_DIR"

  step "Installing script..."
  cp "${SCRIPT_DIR}/${SCRIPT_NAME}" "$INSTALLED_SCRIPT"
  chmod 755 "$INSTALLED_SCRIPT"
  info "Copied to $INSTALLED_SCRIPT"

  step "Generating launchd plist..."

  local program_args
  program_args=$(build_program_arguments)

  # Build the plist from scratch (avoids fragile sed on the template)
  cat > "$INSTALLED_PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.nextdns-update</string>

  <key>ProgramArguments</key>
  <array>
${program_args}
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ThrottleInterval</key>
  <integer>30</integer>

  <key>StandardOutPath</key>
  <string>${LOG_DIR}/nextdns-update.log</string>

  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/nextdns-update.error.log</string>
</dict>
</plist>
PLIST_EOF

  chmod 644 "$INSTALLED_PLIST"
  info "Written to $INSTALLED_PLIST"

  step "Loading launchd agent..."
  # Unload first if already loaded (idempotent reinstall)
  launchctl unload "$INSTALLED_PLIST" 2>/dev/null || true
  launchctl load -w "$INSTALLED_PLIST"
  info "Agent loaded and enabled."

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  NextDNS IP updater installed successfully!                 │"
  echo "  │                                                             │"
  printf "  │  ID         : %-45s│\n" "${NEXTDNS_ID}"
  printf "  │  Token      : %-45s│\n" "${NEXTDNS_TOKEN}"
  printf "  │  Interval   : %-3ss%-42s│\n" "${INTERVAL}" ""
  if [[ -n "$ALLOWED_MACS" ]]; then
    printf "  │  MAC filter : %-45s│\n" "${ALLOWED_MACS}"
  else
    echo "  │  MAC filter : disabled (updates on any network)             │"
  fi
  echo "  │                                                             │"
  echo "  │  Logs: ~/Library/Logs/nextdns-update/                      │"
  echo "  │                                                             │"
  echo "  │  To uninstall: ./install.sh --uninstall                    │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
parse_args "$@"
$UNINSTALL && do_uninstall
do_install
