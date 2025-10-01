#!/usr/bin/env bash
#
# iphone-socks.sh — Auto-apply a SOCKS proxy to the iPhone USB tethering service on macOS.
# - Idempotent: only changes state when needed
# - Safe: verifies service existence/activeness and current proxy settings
# - Flexible: supports overrides, dry-run, and clean disable
#
# Usage:
#   iphone-socks.sh                # auto-detect iPhone USB service; enable SOCKS if active, disable otherwise
#   iphone-socks.sh on             # force enable on detected/overridden service
#   iphone-socks.sh off            # force disable on detected/overridden service
#   iphone-socks.sh status         # print detected service + current proxy status
#   iphone-socks.sh --dry-run ...  # show what would change
#
# Env overrides:
#   SOCKS_HOST=127.0.0.1 SOCKS_PORT=9001
#   IPHONE_SERVICE="iPhone USB"      # exact Network Service name (preferred if you know it)
#   MATCHERS="iPhone USB|iPhone|USB iPhone|iPad USB|iPad"   # pipe-separated regex for service-name matching
#   BYPASS="localhost|127.0.0.1|*.local"    # pipe-separated list merged (idempotently)
#
set -euo pipefail

# ---- Config (defaults) -------------------------------------------------------
SOCKS_HOST="${SOCKS_HOST:-127.0.0.1}"
SOCKS_PORT="${SOCKS_PORT:-9001}"
IPHONE_SERVICE="${IPHONE_SERVICE:-}"                 # if set, used directly (no autodetect)
MATCHERS="${MATCHERS:-iPhone USB|iPhone|USB iPhone|iPhone USB 1|iPhone USB 2|iPhone USB 3|iPhone USB 4|iPhone USB 5|iPhone USB 6|iPad USB|iPad}"
BYPASS_DEFAULT="localhost|127.0.0.1|*.local|172.20.10.1"
BYPASS="${BYPASS:-$BYPASS_DEFAULT}"

DRY_RUN=false
ACTION="auto"  # auto|on|off|status

# ---- Helpers -----------------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

run() {
  if $DRY_RUN; then
    printf '[dry-run] %q ' "$@"; printf '\n'
    return 0
  fi
  "$@"
}

# Trim spaces
trim() { awk '{$1=$1;print}' <<<"${1:-}"; }

ns() { /usr/sbin/networksetup "$@"; }

# Return all Network Service names (one per line)
list_services() {
  # Safe even on localized systems; service lines begin without leading spaces
  ns -listallnetworkservices 2>/dev/null | sed '1d' || true
}

# Map Service -> Device (enX/pdpx) using -listnetworkserviceorder
service_to_device() {
  local svc="$1"
  /usr/sbin/networksetup -listnetworkserviceorder 2>/dev/null \
    | awk -v s="$svc" '
        BEGIN{IGNORECASE=1}
        /^\([0-9]+\)/{name=$0; sub(/^\([0-9]+\) /,"",name)}
        /Device: /{
          dev=$0; sub(/^.*Device: /,"",dev); sub(/\).*$/,"",dev)
          if (name==s) {print dev; exit}
        }'
}

# Returns 0 (true) iff the network service currently has a valid IPv4 address.
service_is_active() {
  local svc="$1"
  local ip_line ip

  # Some macOS builds omit the line entirely when inactive.
  ip_line=$(ns -getinfo "$svc" 2>/dev/null | grep -E '^IP address' || true)
  [[ -n "$ip_line" ]] || return 1

  ip=${ip_line#IP address: }
  [[ -n "$ip" && "$ip" != "none" ]] || return 1

  # Basic IPv4 sanity check.
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  return 0
}

# Get current SOCKS settings for a service: "host port state"
get_socks() {
  local svc="$1"
  # Output lines:
  # "Enabled: Yes/No"
  # "Server:  127.0.0.1"
  # "Port:    9001"
  local enabled host port
  enabled=$(ns -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': *' '/^Enabled/{print $2}')
  host=$(   ns -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': *' '/^Server/{print $2}')
  port=$(   ns -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': *' '/^Port/{print $2}')
  printf '%s %s %s\n' "${host:-}" "${port:-}" "${enabled:-No}"
}

# Set bypass list idempotently (merge w/out duplicates)
merge_and_set_bypass() {
  local svc="$1"
  local wanted_raw="${2:-$BYPASS}"
  local wanted_sep="|"

  # Current
  local current
  current=$(ns -getproxybypassdomains "$svc" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)

  # Normalize to set
  local tmpfile
  tmpfile=$(mktemp)
  {
    tr '|' '\n' <<<"$wanted_raw"
    printf '%s\n' "$current"
  } | sed '/^$/d' | awk '!seen[tolower($0)]++' >"$tmpfile"

  local merged
  merged=$(paste -sd ' ' "$tmpfile")
  rm -f "$tmpfile"

  # Only set if changed
  local current_norm
  current_norm=$(echo "$current" | tr '\n' ' ' | awk '{$1=$1;print}')
  if [[ "$merged" != "$current_norm" ]]; then
    run ns -setproxybypassdomains "$svc" $merged
    log "[iphone-socks] Set bypass on \"$svc\": $merged"
  fi
}

# Enable SOCKS (host/port) if not already correct
enable_socks() {
  local svc="$1" host="$2" port="$3"
  local cur_host cur_port cur_state
  read -r cur_host cur_port cur_state < <(get_socks "$svc")

  if [[ "$cur_host" == "$host" && "$cur_port" == "$port" && "$cur_state" =~ ^(Yes|On|1)$ ]]; then
    log "[iphone-socks] SOCKS already enabled on \"$svc\" -> $host:$port"
  else
    # Set without auth; the final 'off' arg prevents PAC (legacy quirk)
    run ns -setsocksfirewallproxy "$svc" "$host" "$port" off
    run ns -setsocksfirewallproxystate "$svc" on
    log "[iphone-socks] Enabled SOCKS on \"$svc\" -> $host:$port"
  fi
}

# Disable SOCKS if currently on
disable_socks() {
  local svc="$1"
  local _h _p cur_state
  read -r _h _p cur_state < <(get_socks "$svc")
  if [[ "$cur_state" =~ ^(Yes|On|1)$ ]]; then
    run ns -setsocksfirewallproxystate "$svc" off
    log "[iphone-socks] Disabled SOCKS on \"$svc\""
  else
    log "[iphone-socks] SOCKS already disabled on \"$svc\""
  fi
}

# Detect the active iPhone/iPad USB tether service.
# Honors IPHONE_SERVICE (explicit override) and MATCHERS (regex on service name).
# Falls back to any *active* service in the common iOS hotspot subnet 172.20.10.x.
detect_iphone_service() {
  # 1) Exact override (no activity check here—caller can decide how to use it)
  if [[ -n "${IPHONE_SERVICE:-}" ]]; then
    printf '%s\n' "$IPHONE_SERVICE"
    return 0
  fi

  # 2) Prefer active services whose *name* matches iPhone/iPad patterns
  local svc
  while IFS= read -r svc; do
    svc=$(trim "$svc")
    [[ -z "$svc" || "$svc" == "*"* ]] && continue   # skip blank/disabled
    if [[ "$svc" =~ (${MATCHERS}) ]] && service_is_active "$svc"; then
      printf '%s\n' "$svc"
      return 0
    fi
  done < <(list_services)

  # 3) Fallback: any *active* service with a 172.20.10.x IPv4 (typical iOS hotspot)
  while IFS= read -r svc; do
    svc=$(trim "$svc")
    [[ -z "$svc" || "$svc" == "*"* ]] && continue
    if service_is_active "$svc"; then
      local ip_line ip
      ip_line=$(ns -getinfo "$svc" 2>/dev/null | grep -E '^IP address' || true)
      ip=${ip_line#IP address: }
      if [[ "$ip" =~ ^172\.20\.10\.[0-9]+$ ]]; then
        printf '%s\n' "$svc"
        return 0
      fi
    fi
  done < <(list_services)

  return 1
}

print_status() {
  local svc="$1"
  local host port state
  read -r host port state < <(get_socks "$svc")
  local active="No"
  service_is_active "$svc" && active="Yes"
  cat <<EOF
Service:         $svc
Active now:      $active
SOCKS Enabled:   $state
SOCKS Endpoint:  ${host:-<none>}:${port:-<none>}
Bypass Domains:  $(ns -getproxybypassdomains "$svc" 2>/dev/null | tr '\n' ' ')
Device (if any): $(service_to_device "$svc" 2>/dev/null || echo "-")
EOF
}

# ---- Parse args --------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    on|off|status|auto) ACTION="$arg" ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# ---- Main --------------------------------------------------------------------
main() {
  local svc
  if ! svc=$(detect_iphone_service); then
    die "Could not find an iPhone/iPad USB tether service. Consider setting IPHONE_SERVICE env or adjusting MATCHERS."
  fi
  svc=$(trim "$svc")

  case "$ACTION" in
    status)
      print_status "$svc"
      exit 0
      ;;
    on)
      enable_socks "$svc" "$SOCKS_HOST" "$SOCKS_PORT"
      merge_and_set_bypass "$svc" "$BYPASS"
      ;;
    off)
      disable_socks "$svc"
      ;;
    auto)
      if service_is_active "$svc"; then
        enable_socks "$svc" "$SOCKS_HOST" "$SOCKS_PORT"
        merge_and_set_bypass "$svc" "$BYPASS"
      else
        disable_socks "$svc"
      fi
      ;;
  esac
}

main "$@"