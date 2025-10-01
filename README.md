# iPhone SOCKS Proxy Script for macOS

## Overview
On macOS, when you tether through **iPhone USB**, the Network Preferences pane does not expose proxy settings — unlike Wi-Fi or Ethernet.  
This script provides a **safe, idempotent command-line tool** to enable, disable, or check a **SOCKS proxy** on the tethered iPhone network service.

It’s ideal if you run a local SOCKS proxy (e.g. SSH tunnel, Tor, VPN) and need a fast way to attach it to the iPhone USB interface.

---

## Features
- 🔍 Auto-detects the correct **iPhone/iPad USB service**  
- ✅ Skips **inactive or disabled** services  
- 🔁 **Idempotent**: applies changes only if needed  
- 📡 Verifies an **active IPv4 address** before enabling  
- 🌐 Configurable via environment variables (`SOCKS_HOST`, `SOCKS_PORT`, `MATCHERS`, `IPHONE_SERVICE`)  
- 📜 Clear subcommands: `on`, `off`, `auto`, `status`, `--dry-run`  

---

## Usage

Enable SOCKS proxy (default: `127.0.0.1:9001`):

```bash
./iphone-socks.sh on
```
Disable SOCKS proxy:
```bash
./iphone-socks.sh off
```
Auto mode: enable if service is active, disable otherwise:
```bash
./iphone-socks.sh auto
```
Check current proxy status:
```bash
./iphone-socks.sh status
```
Dry run (show actions without applying):
```bash
./iphone-socks.sh --dry-run auto
```

## Configuration

You can override defaults via environment variables: 
```bash
SOCKS_HOST=127.0.0.1 SOCKS_PORT=9050 ./iphone-socks.sh on
IPHONE_SERVICE="iPhone USB" ./iphone-socks.sh auto
```

## Why

Unlike Wi-Fi/Ethernet, macOS doesn’t provide UI to configure proxies for iPhone USB tethering.
This script closes that gap, giving developers and power users a fast, repeatable way to attach SOCKS proxies without digging into network preferences.










