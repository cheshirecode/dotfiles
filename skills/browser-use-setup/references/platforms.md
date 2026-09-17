# Platform notes

Read when the install or connection fails, on Linux/headless/CI, or before a
first connection on a new machine.

## macOS

1. **One-time Chrome toggle** — in Chrome, open
   `chrome://inspect/#remote-debugging` and tick
   "Allow remote debugging for this browser instance". This step is
   intentionally manual; the harness cannot reach it until CDP is available.
   Without it the daemon log ends in `DevToolsActivePort not found` under
   `~/.config/browser-harness/tmp/`.
2. **Per-connection Allow sheet** — Chrome shows an "Allow remote debugging?"
   sheet per connection. `browser-use mac-approve` clicks it without
   foregrounding Chrome; it needs **Accessibility** permission for the app
   that launched the CLI (Ghostty, Terminal, iTerm, an IDE — not the shell).
   `ready` means continue; `accessibility-required` means grant it.
3. **TCC grant is not retroactive** — Accessibility granted mid-session does
   not propagate to processes already running. Restart the terminal app (and
   the session in it) after granting, or click Allow by hand per connection.
4. Doctor lanes: `chrome running`, `daemon alive`, `active browser
   connections`. Cloud auth lane is optional and may stay FAIL.

## Linux

- **Snap Chromium** blocks CDP by default. If `snap list chromium` shows it,
  run `browser-use doctor --fix-snap` and follow the printed fix.
- **Headless servers** (no `DISPLAY`/`WAYLAND_DISPLAY`) have no local browser
  to attach to. Either point `BU_CDP_WS` at a remote browser's CDP endpoint
  or use cloud browsers (`browser-use auth login`, then `start_remote_daemon`
  by name; select with `BU_NAME=<name>`).
- Debian/Ubuntu: the uv tool install needs only curl + ca-certificates. The
  dotfiles `Dockerfile.test-matrix` runs this installer on ubuntu:24.04 in CI
  as the Linux proof.

## Sandbox testing (either OS)

The installer never needs to touch the host:

```bash
export SANDBOX="$PWD/.bu-sandbox"
mkdir -p "$SANDBOX/home"
HOME="$SANDBOX/home" \
UV_TOOL_DIR="$SANDBOX/uv-tools" \
UV_TOOL_BIN_DIR="$SANDBOX/uv-bin" \
bash bin/install-browser-use.sh
PATH="$SANDBOX/uv-bin:$PATH" bin/bu --version
```

Everything — binary, vendor skill registration, browser-harness state — lands
under `$SANDBOX`. Delete the directory to uninstall the test completely.

## Windows

Unsupported natively. Run inside WSL2; the installer refuses with exit 1 and
names WSL.

WSL2 with the browser on the Windows side: Chromium binds CDP to `127.0.0.1`
only (`--remote-debugging-address` is ignored in headful mode), so WSL
reaches it through the gateway. One-time elevated-PowerShell setup on
Windows:

```powershell
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=9223 connectaddress=127.0.0.1 connectport=9222
netsh advfirewall firewall add rule name="WSL Brave CDP" dir=in action=allow protocol=TCP localport=9223
```

Then relaunch the browser with `--remote-debugging-port=9222` and use `bu`
normally: the wrapper probes `<gateway>:9223` (portproxy lane), then
`localhost:9222` (mirrored networking), exports `BU_CDP_URL`, and prints one
`wired` line. The gateway IP changes across WSL restarts; the wrapper
re-resolves it per invocation. Remove the proxy with
`netsh interface portproxy delete v4tov4 listenport=9223` when done.

## Still broken

`browser-use --doctor` classifies: `chrome running` FAIL → open Chrome or use
a cloud browser; `daemon alive` FAIL → the toggle above, Chrome closed, or an
unreachable CDP endpoint (check the log under
`${XDG_CONFIG_HOME:-~/.config}/browser-harness/tmp/`). `--doctor` also prints
when an update is available: `browser-use --update -y` (or re-run the
installer, which always upgrades).
