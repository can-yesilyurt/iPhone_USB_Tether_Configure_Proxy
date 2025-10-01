# iPhone_USB_Tether_Configure_Proxy
iphone-socks.sh — Auto-apply a SOCKS proxy to the iPhone USB tethering service on macOS.

- Idempotent: only changes state when needed
- Safe: verifies service existence/activeness and current proxy settings
- Flexible: supports overrides, dry-run, and clean disable
#
Usage:
  iphone-socks.sh                auto-detect iPhone USB service; enable SOCKS if active, disable otherwise
  iphone-socks.sh on             force enable on detected/overridden service
  iphone-socks.sh off            force disable on detected/overridden service
  iphone-socks.sh status         print detected service + current proxy status
  iphone-socks.sh --dry-run ...  show what would change
#
Env overrides:
  SOCKS_HOST=127.0.0.1 SOCKS_PORT=9001
  IPHONE_SERVICE="iPhone USB"      exact Network Service name (preferred if you know it)
  MATCHERS="iPhone USB|iPhone|USB iPhone|iPad USB|iPad"   pipe-separated regex for service-name matching
  BYPASS="localhost|127.0.0.1|*.local"    pipe-separated list merged (idempotently)
#
