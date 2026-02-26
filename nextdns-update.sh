#!/usr/bin/env zsh
# nextdns-update.sh — Periodically update NextDNS linked IP
#
# Usage:
#   nextdns-update.sh [options]
#
# Options:
#   -u, --url <url>            NextDNS linked-IP URL (required)
#                              e.g. https://link-ip.nextdns.io/{id}/{token}
#   -i, --interval <seconds>   Polling interval in seconds (default: 300)
#   -m, --macs <mac,...>       Comma-separated list of allowed router MAC addresses
#                              (if omitted, always updates regardless of network)
#   -o, --once                 Run once and exit (no loop)
#   -v, --verbose              Enable verbose logging
#   -h, --help                 Show this help message

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
readonly DEFAULT_INTERVAL=300   # 5 minutes
readonly LOG_TAG="nextdns-update"

INTERVAL=$DEFAULT_INTERVAL
NEXTDNS_URL=""
NEXTDNS_ID=""
NEXTDNS_TOKEN=""
ALLOWED_MACS=()
RUN_ONCE=false
VERBOSE=false

# ── Helpers ───────────────────────────────────────────────────────────────────
log()    { syslog -s -l notice  -k Facility com.apple.console "[$LOG_TAG] $*" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  $*"; }
warn()   { syslog -s -l warning -k Facility com.apple.console "[$LOG_TAG] $*" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  $*" >&2; }
err()    { syslog -s -l err     -k Facility com.apple.console "[$LOG_TAG] $*" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2; }
debug()  { $VERBOSE && echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $*" || true; }

usage() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
  exit 0
}

die() { err "$*"; exit 1; }

# ── URL parsing ───────────────────────────────────────────────────────────────
parse_nextdns_url() {
  local url="$1"
  # Expected format: https://link-ip.nextdns.io/{id}/{token}
  if [[ "$url" =~ ^https://link-ip\.nextdns\.io/([^/]+)/([^/]+)$ ]]; then
    NEXTDNS_ID="${match[1]}"
    NEXTDNS_TOKEN="${match[2]}"
    NEXTDNS_URL="$url"
  else
    die "Invalid NextDNS URL: '$url'\n       Expected format: https://link-ip.nextdns.io/{id}/{token}"
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--url)     parse_nextdns_url "$2"; shift 2 ;;
      -i|--interval) INTERVAL="$2"; shift 2 ;;
      -m|--macs)
        IFS=',' read -rA ALLOWED_MACS <<< "$2"
        shift 2
        ;;
      -o|--once)    RUN_ONCE=true; shift ;;
      -v|--verbose) VERBOSE=true; shift ;;
      -h|--help)    usage ;;
      *) die "Unknown option: $1. Use -h for help." ;;
    esac
  done

  [[ -n "$NEXTDNS_URL" ]] || die "NextDNS URL is required (-u/--url)."

  if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
    die "Interval must be a positive integer."
  fi
}

# ── Router MAC detection ──────────────────────────────────────────────────────
get_router_mac() {
  local gateway mac
  gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
  [[ -z "$gateway" ]] && return 1
  mac=$(arp -n "$gateway" 2>/dev/null | awk '{print $4}')
  [[ -z "$mac" || "$mac" == "(incomplete)" ]] && return 1
  echo "$mac"
}

is_mac_allowed() {
  # If no MAC allowlist configured → always allowed
  if [[ ${#ALLOWED_MACS[@]} -eq 0 ]]; then
    debug "No MAC filter configured — proceeding."
    return 0
  fi

  local current_mac
  current_mac=$(get_router_mac)

  if [[ -z "$current_mac" ]]; then
    warn "Could not detect router MAC address — skipping update."
    return 1
  fi

  log "Router MAC: '$current_mac'"

  for allowed in "${ALLOWED_MACS[@]}"; do
    if [[ "${current_mac:l}" == "${allowed:l}" ]]; then
      debug "MAC '$current_mac' is in the allowlist."
      return 0
    fi
  done

  log "MAC '$current_mac' not in allowlist [${(j:, :)ALLOWED_MACS}] — skipping update."
  return 1
}

# ── NextDNS IP update ─────────────────────────────────────────────────────────
update_ip() {
  local http_code

  debug "Calling: $NEXTDNS_URL"

  http_code=$(curl --silent --show-error --output /dev/null \
    --write-out "%{http_code}" \
    --max-time 10 \
    --retry 3 \
    --retry-delay 2 \
    --retry-connrefused \
    "$NEXTDNS_URL" 2>&1) || {
    warn "curl failed for $NEXTDNS_URL"
    return 1
  }

  if [[ "$http_code" == "200" ]]; then
    log "IP updated successfully (HTTP $http_code)."
  else
    warn "Unexpected HTTP response: $http_code"
    return 1
  fi
}

# ── Main loop ─────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  log "Starting NextDNS IP updater (ID=${NEXTDNS_ID}, token=${NEXTDNS_TOKEN}, interval=${INTERVAL}s)."
  if [[ ${#ALLOWED_MACS[@]} -gt 0 ]]; then
    log "MAC filter: ${(j:, :)ALLOWED_MACS}"
  else
    log "MAC filter: disabled (updates on any network)."
  fi

  while true; do
    if is_mac_allowed; then
      update_ip || true   # non-fatal — keep looping
    fi

    $RUN_ONCE && break

    debug "Sleeping ${INTERVAL}s..."
    sleep "$INTERVAL"
  done
}

main "$@"
