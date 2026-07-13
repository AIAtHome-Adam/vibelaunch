# VibeLaunch

Windows session manager for [VibeKeys Max](https://vibekeys.dev) + [vibetty](https://github.com/second-state/vibetty). Picks a preset, stops any existing vibetty on your configured port, and spawns a new PTY session (Claude, Codex, Hermes, OpenClaw, ACP variants).

**Status (Jul 2026):** **Publish-ready** — preset CLI + WPF GUI verified with keypad voice for **Codex**, **Hermes**, and **OpenClaw**. WPF-UI GUI (WebView2 embed). ACP harness presets are included as examples and require local configuration.

Shipped layout: `C:\Program Files\VibeLaunch\` (separate from official `C:\Program Files (x86)\Vibekeys\`).

**Before you publish:** fill in personal Connect links — copy [`config/gui-links.local.json.example`](config/gui-links.local.json.example) to `%LOCALAPPDATA%\VibeLaunch\gui-links.local.json` (GitHub, YouTube, X, Buy Me a Coffee, LinkedIn). Empty keys hide the matching menu items.

---

## What it does

```text
  vibelaunch <preset> [--force]
       │
       ├── preflight (port, PATH, firewall hints)
       ├── kill vibetty tree on configured port (with --force)
       └── spawn vibetty → PTY (Windows CLI or WSL via bash -lic)
```

VibeLaunch manages **Windows vibetty only**. It does **not** start or stop WSL gateways (OpenClaw `:18789`, Hermes dashboard).

---

## Quick start

### Dev From Repo

```powershell
cd C:\Users\<windows-user>\Documents\Workspaces\vibelaunch
.\setup-wsl-remote.ps1       # prompts for WSL username + LAN IP, writes %LOCALAPPDATA%\VibeLaunch\defaults.local.json (port 3001)
.\vibelaunch.cmd preflight   # expect port 3001, WSL enabled, wsl.user OK
.\vibelaunch.cmd codex-workspace --force
.\vibelaunch.cmd hermes-vk --force
.\vibelaunch.cmd openclaw --force    # → openclaw-vk (session vibekeys)
.\vibelaunch.cmd status
.\vibelaunch.cmd stop --force
```

Use `.\vibelaunch.cmd` from the repo until `install.ps1` adds VibeLaunch to PATH.

### Install (Administrator)

```powershell
& "C:\Users\<windows-user>\Documents\Workspaces\vibelaunch\install.ps1"
```

Open a **new** terminal, then `vibelaunch list` (no `.\` prefix).

### GUI

`vibelaunch-gui.cmd` or `.\vibelaunch-gui.ps1` — WPF-UI GUI, builds to `VibeLaunchGui.Fluent.exe`.

From **PowerShell**, prefer `.\vibelaunch-gui.ps1` (CMD `start` can be flaky when invoked from PowerShell).

If the WPF exe is not built, the launcher falls back to WinForms `gui/vibelaunch-gui.ps1`.

---

## Daily Presets

| Preset | CLI | Agent | Voice | Notes |
|--------|-----|-------|-------|-------|
| **codex** | `vibelaunch codex --force` | Codex (Windows) | verified | Default Codex at configured cwd |
| **codex-workspace** | `vibelaunch codex-workspace --force` | Codex (Windows) | verified | Codex in `{{workspaces.default}}` |
| **hermes-vk** | `vibelaunch hermes-vk --force` | Hermes | verified | Auto WSL/Windows; direct launch with vibetty-native scroll |
| **openclaw-vk** | `vibelaunch openclaw --force` | OpenClaw TUI | verified | `--session vibekeys` — recommended for keypad |
| **claude** | `vibelaunch claude --force` | Claude Code | verified | Windows-native |
| **openclaw-tui** | `vibelaunch openclaw main --force` | OpenClaw main session | ✅ connects | Heartbeat poll spam on small screen — use for debugging only |

Hybrid tokens resolve the same presets: `codex workspace`, `hermes`, `openclaw`, `openclaw main`.

### `--force`

`--force` is **VibeLaunch-only** — kills the existing vibetty tree and switches preset. Never pass `--force` to spawned CLIs (OpenClaw/Hermes/Codex do not accept it).

Passthrough args to the spawned CLI use `--`:

```cmd
vibelaunch claude -- -c --dangerously-skip-permissions
vibelaunch codex-workspace -- --resume
```

Block in the current window instead of a new console: `vibelaunch codex-workspace --wait`.

---

## All presets

| Name | Tokens | Platform | Spawn summary |
|------|--------|----------|---------------|
| `claude` | `claude` | Windows | `claude` |
| `claude-resume` | `claude resume` | Windows | `claude -c` (resume) |
| `codex` | `codex` | Windows | `codex` @ config `cwd` |
| `codex-workspace` | `codex workspace` | Windows | `codex` @ configured workspace |
| `cmd-scroll-test` | `cmd scroll test` | Windows | scrollback diagnostic |
| `hermes-vk` | `hermes` | **auto** | WSL or Windows `hermes chat --skills vibekeys-hermes` |
| `hermes-vk-wsl` | `hermes wsl` | WSL | force WSL Hermes |
| `hermes-vk-win` | `hermes windows` | Windows | force native Hermes |
| `hermes-codex-workspace` | `hermes codex workspace` | WSL | Hermes `-m openai-codex/gpt-5.4` |
| `hermes-codex-workspace-win` | `hermes codex windows` | Windows | same model route on Windows PATH |
| `openclaw-vk` | `openclaw` | WSL | `openclaw tui --session vibekeys` |
| `openclaw-tui` | `openclaw main` | WSL | `openclaw tui` (main session) |
| `openclaw-cursor-workspace` | `openclaw cursor workspace` | WSL | ACP spawn cursor — **configure ACP locally** |
| `openclaw-codex-workspace` | `openclaw codex workspace` | WSL | ACP spawn codex — **configure ACP locally** |
| `hermes-acp-cursor` | `hermes acp cursor` | WSL | Hermes ACP *client* drop-in to live Cursor — **verified** |
| `hermes-acp-claude` | `hermes acp claude` | WSL | Hermes ACP *client* drop-in to Claude Code — **verified** |
| `hermes-acp-codex` | `hermes acp codex` | WSL | Hermes ACP *client* drop-in to Codex — **verify `codex login`** |

`vibelaunch list` shows platform hints and per-preset notes. **`hermes`** auto-picks WSL when `wsl.enabled` and hermes is in WSL, else Windows PATH; override with `hermes wsl` / `hermes windows`. **OpenClaw** presets are WSL-only (no native Windows companion yet).

---

## Profiles: Standalone Vs WSL Remote

| | **standalone** (public default) | **wsl-remote** (WSL remote example) |
|--|--------------------------------|---------------------------|
| vibetty port | **3000** (upstream default) | **3001** (Mission Control uses 3000 in WSL) |
| Keypad URL | `ws://<LAN-IP>:3000/ws` | `ws://<LAN-IP>:3001/ws` |
| WSL agents | Optional | Required (`bash -lic`) |

Set profile in `config\defaults.json` or machine overlay:

`%LOCALAPPDATA%\VibeLaunch\defaults.local.json`

WSL profile one-liner: `.\setup-wsl-remote.ps1` — prompts for your WSL username and LAN IP (auto-detect suggested, editable) and writes them into the file below; re-run anytime to change them. Non-interactive: `.\setup-wsl-remote.ps1 -WslUser <name> -KeypadHost <ip>`.

```json
{
  "profile": "wsl-remote",
  "port": 3001,
  "keypadHost": "<LAN-IP>",
  "wsl": { "enabled": true, "user": "<wsl-user>" }
}
```

`config/defaults.local.json.example` ships with `<LAN-IP>` / `<wsl-user>` placeholders — `setup-wsl-remote.ps1` replaces them for you; editing the file by hand works too. `vibelaunch preflight` fails fast with a clear message if `wsl.user` is still blank or a placeholder when a WSL preset needs it.

> **Footer lie:** vibetty may show `http://localhost:3001` even when bound to `0.0.0.0`. Trust `vibelaunch status` / `preflight`, not the footer.

---

## Config files

| File | Purpose |
|------|---------|
| `config/defaults.json` | Shipped defaults (standalone-oriented) |
| `config/profiles/*.json` | Profile overlays |
| `config/presets.json` | Launch recipes |
| `config/presets.local.json` | Your overrides (gitignored) |
| `%LOCALAPPDATA%\VibeLaunch\defaults.local.json` | Machine-specific defaults |
| `%LOCALAPPDATA%\VibeLaunch\state.json` | Last launched preset / PID |

Template variables: `{{workspaces.default}}`, `{{workspaces.default-wsl}}`, `{{cwd}}`, `{{host}}`, `{{port}}`, `{{wsl.user}}` (resolves from `config.wsl.user` — used by every WSL-based preset's `wsl.exe -u {{wsl.user}}` spawn instead of a hardcoded username).

---

## Launch recipes (CLI reference)

### Windows-native (after `vibetty --`)

| Tool | Useful flags |
|------|----------------|
| `claude` | `-c`, `--dangerously-skip-permissions` |
| `codex` | Interactive TUI; must be on PATH (see Codex PATH self-heal in runbook) |

### Hermes (WSL or Windows native)

| Preset / flag | Purpose |
|---------------|---------|
| `hermes` | Auto: WSL if `wsl.enabled`, else Windows PATH |
| `hermes wsl` / `hermes windows` | Force platform |
| `-m` / `--model` | Model override (e.g. `hermes-codex-workspace` presets) |
| `--skills vibekeys-hermes` | Preloaded in all `hermes-vk*` presets |
| `--continue` / `--resume` | Resume session (in-chat; no separate preset) |
| `--yolo` | Auto-approve tools |

`hermes acp` is an editor stdio server — not OpenClaw `/acp spawn`. Hermes presets land in `hermes chat`; backend pivots are in-session.

Source: [Hermes CLI reference](https://hermes-agent.nousresearch.com/docs/reference/cli-commands).

### OpenClaw (WSL, `openclaw tui`)

| Flag | Purpose |
|------|---------|
| `--url ws://127.0.0.1:18789` | Gateway URL |
| `--session <key>` | Session key (`vibekeys` for keypad; `main` for gateway default) |
| **`--message "<text>"`** | Initial message after connect (ACP presets) |
| `--thinking`, `--deliver` | Model / channel behavior |

ACP in TUI (or via `--message` at launch):

```text
/acp spawn <harness-id> [--mode persistent|oneshot] [--thread auto|here|off] [--bind here|off] [--cwd <path>] [--label <label>]
```

Harness ids: `cursor`, `codex`, `claude`, `gemini`, …

Example preset spawn (OpenClaw Cursor on a configured workspace):

```text
openclaw tui --message "/acp spawn cursor --cwd /mnt/c/.../Example-Workspace --mode persistent"
```

Sources: [OpenClaw TUI CLI](https://docs.openclaw.ai/cli/tui), [ACP agents](https://docs.openclaw.ai/tools/acp-agents).

### Spawn patterns

| Pattern | When |
|---------|------|
| `spawn` only | claude, codex, openclaw tui, hermes wrapper |
| `spawn` + OpenClaw `--message` | OpenClaw ACP landing at connect |
| `postLaunch` (schema field, future) | Hermes in-session or if `--message` timing fails on device |

---

### Hermes ACP client presets (drop-in coding sessions)

These presets launch **Hermes's own ACP *client*** (`tools/hermes-acp-client.py`)
into a live coding-agent session from the keypad — no OpenClaw harness needed.
They spawn a persistent shell; type prompts, `exit` (or Ctrl-D) quits back to
VibeLaunch. All are WSL presets (the adapter runs on `python3` in WSL).

```cmd
vibelaunch hermes-acp-cursor --force     # drop into live Cursor  (verified)
vibelaunch hermes-acp-claude  --force     # drop into live Claude Code (verified)
vibelaunch hermes-acp-codex   --force     # drop into live Codex (verify codex login)
```

Requirements per agent (subscription auth — no API keys):

| Preset | Agent | Requires |
|--------|-------|----------|
| `hermes-acp-cursor` | Cursor (`agent acp`) | Cursor Pro `agent` auth (`agent login`) |
| `hermes-acp-claude` | Claude Code | Node + `npx @agentclientprotocol/claude-agent-acp` + Claude Pro auth |
| `hermes-acp-codex` | Codex | Node + `npx @zed-industries/codex-acp` + Codex ChatGPT auth (`codex login`) |

> **Codex note:** if `hermes-acp-codex` (or plain `codex`) 401s with
> `token_invalidated` / `refresh_token_invalidated`, your Codex ChatGPT token
> was revoked — re-run `codex login`. This is account-wide, not an adapter bug.
> The adapter + ACP handshake are verified working.

Under the hood each preset runs:

```bash
python3 ~/bin/hermes-acp-client.py shell <cursor|claude|codex> \
  --cwd {{workspaces.default-wsl}} --approve
```

For one-shot (non-interactive) delegation, use `send` instead of `shell`. Full
docs: [HERMES_ACP_CLIENT.md](docs/HERMES_ACP_CLIENT.md).

---

## CLI commands

| Command | Purpose |
|---------|---------|
| `vibelaunch` | Default preset |
| `vibelaunch <preset\|tokens…>` | Hybrid preset resolution |
| `vibelaunch <preset> --dry-run` | Print resolved cwd/spawn without launching (skips kill prompt) |
| `vibelaunch list` | Presets |
| `vibelaunch status` | Port, PID, preset, keypad URL |
| `vibelaunch stop [--force]` | Kill vibetty tree |
| `vibelaunch preflight` | PATH, firewall, port |
| `vibelaunch config path` | Config file paths |
| `vibelaunch run --spawn '…' [--cwd '…']` | Raw spawn escape hatch |
| `vibelaunch status --json` | JSON status (GUI) |
| `vibelaunch gui-config` | Merged GUI settings JSON |
| `vibelaunch gui-links` | Help/hardware link URLs + runbook path |
| `vibelaunch paths --json` | Install paths (presets, PTY presets, user config) |
| `vibelaunch gui-save --cols N --rows N` | Persist GUI size to `%LOCALAPPDATA%\VibeLaunch\gui.local.json` |

### GUI launch flags

| Flag | Purpose |
|------|---------|
| `--gui` | Use saved GUI geometry + hide-console preference |
| `--cols N` / `--rows N` | PTY size applied at launch (keypad readability) |
| `--hide-console` / `--show-console` | Hide or show the separate vibetty console window |

---

## Known issues (upstream / agent — not VibeLaunch bugs)

| Issue | Workaround |
|-------|------------|
| OpenClaw doctor / plugin metadata warnings on TUI startup | Harmless housekeeping; fix in OpenClaw when convenient |
| OpenClaw **main** session heartbeat spam on small screen | Use `openclaw-vk` (`--session vibekeys`) for daily keypad use |
| vibetty footer shows `localhost` | Display bug — verify bind with `vibelaunch status` |
| Keypad won't connect despite Allow rule | Firewall **Block** rule on `vibetty.exe` beats Allow — see runbook |
| Codex instant exit | Stale shell — `codex` not on PATH; fresh terminal or CodexPathSelfHeal |

Full troubleshooting: [VIBEKEYS_REMOTE.md](docs/VIBEKEYS_REMOTE.md).

---

## Roadmap

### Shipped (Jul 2026)

| Item | Notes |
|------|-------|
| CLI preset switcher | Hybrid tokens, `--force` kill/switch, preflight, status JSON |
| WPF-UI GUI | WebView2 embed, menus, PTY presets, theme, in-app runbook, keypad readiness (`VibeLaunchGui.Fluent`) |
| PTY size at launch | `mode con` before vibetty spawn; presets JSON + GUI sliders |
| Agent skill | Optional; see [VIBEKEYS_AGENT_SKILLS.md](docs/VIBEKEYS_AGENT_SKILLS.md) |

### Agent skills & `/vibekeys`

Session control from Discord/Signal/Hermes/OpenClaw and compact keypad responses ship under [`skills/`](skills/) and are documented in [VIBEKEYS_AGENT_SKILLS.md](docs/VIBEKEYS_AGENT_SKILLS.md):

| Skill | Role |
|-------|------|
| `vibekeys` | **Canonical** — **`/vibekeys`** slash + NL → launch profiles (incl. Hermes ACP) |
| `vibelaunch` | Thin legacy alias — same CLI, old trigger name |
| `vibekeys-hermes` | In-session compact UX on Hermes keypad |
| `vibekeys-openclaw` | In-session compact UX on OpenClaw keypad |

Copy a skill into your Hermes/OpenClaw skills directory to enable it; VibeLaunch itself does not auto-deploy skills to agent workspaces.

### Stretch goals (deferred)

| Item | Notes |
|------|-------|
| **Mid-session preset switch** | Keep vibetty + keypad WebSocket alive; swap PTY child without keypad reconnect. Needs upstream vibetty support or a wrapper — today `--force` relaunches vibetty and the keypad must reconnect. |
| **Session parking / juggling** | Park multiple agent sessions and hop between them without full restart. Separate from mid-session switch; heavier UX + process model. |
| OpenClaw ACP presets (`openclaw-cursor-workspace`, `openclaw-codex-workspace`) | Presets exist; needs local harness setup + hardware test |
| Hermes ACP presets (`hermes-acp-*`) | Verified stopgap — see [HERMES_ACP_CLIENT.md](docs/HERMES_ACP_CLIENT.md); boost [Hermes #5257](https://github.com/NousResearch/hermes-agent/issues/5257) for native support |
| Named session join | Launch into an ongoing Discord / channel session by session key |
| OpenClaw VibeKeys theming | Compact TUI beyond `vibekeys-openclaw` — see [VIBEKEYS_AGENT_SKILLS.md](docs/VIBEKEYS_AGENT_SKILLS.md) |
| Tailscale away-from-home | Keypad over tailnet — not tested |
| `install.ps1` to PATH | Optional; run as Administrator when ready |

---

## Hermes ACP client (drop-in coding sessions)

VibeLaunch's promise is "every tool in one VibeKeys session." The
[`tools/hermes-acp-client.py`](tools/hermes-acp-client.py) adapter lets Hermes
itself **drop into a live Cursor / Claude Code / Codex / Gemini session** — the
OpenClaw-ACP-style "sit inside the agent" experience, built natively on Hermes
with zero dependencies. From the handheld you can launch Hermes, then have
Hermes enter a coding agent and steer it turn-by-turn.

```bash
python3 tools/hermes-acp-client.py shell cursor --cwd /path/to/repo --approve
```

Full docs: [HERMES_ACP_CLIENT.md](docs/HERMES_ACP_CLIENT.md). This is a stopgap
for the upstream Hermes ask — **[issue #5257](https://github.com/NousResearch/hermes-agent/issues/5257)**
(generalized ACP client in core). Boost it if you want this shipped natively.

---

## Agent skill

See [VIBEKEYS_AGENT_SKILLS.md](docs/VIBEKEYS_AGENT_SKILLS.md) — `/vibekeys`, vibelaunch CLI, and compact keypad response guidance.

---

## Related docs

- [VIBEKEYS_REMOTE.md](docs/VIBEKEYS_REMOTE.md) — public remote-mode runbook (network, ASR, firewall, manual vibetty)
- [VIBEKEYS_AGENT_SKILLS.md](docs/VIBEKEYS_AGENT_SKILLS.md) — optional agent skill routing notes
- [HERMES_ACP_CLIENT.md](docs/HERMES_ACP_CLIENT.md) — Hermes ACP *client*: drop into live Cursor/Claude/Codex/Gemini sessions from Hermes
- [vibekeys.dev remote mode](https://vibekeys.dev/docs/remote-mode/)

---

## GUI (WPF-UI + WebView2)

| Launcher | Project | Exe |
|----------|---------|-----|
| `vibelaunch-gui.cmd` / `.ps1` | `gui/VibeLaunchGui.Fluent/` | `VibeLaunchGui.Fluent.exe` |

WinForms fallback: `gui/vibelaunch-gui.ps1` (no build step; opens browser instead of embed).

### Build (one-time, .NET 8 SDK)

From the **repo root**:

```powershell
dotnet build vibelaunch/gui/VibeLaunchGui.Fluent/VibeLaunchGui.Fluent.csproj -c Release
```

From the **`vibelaunch/`** folder (where `vibelaunch-gui.ps1` lives):

```powershell
dotnet build gui/VibeLaunchGui.Fluent/VibeLaunchGui.Fluent.csproj -c Release
```

Paste only the `dotnet build ...` line — not the `PS C:\...>` prompt.

Requires [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (preinstalled on Windows 11).

### Features

- **Menu bar:** VibeKeys Hardware (setup, [firmware](https://vibekeys.dev/docs/flashing-firmware/), remote docs) · Settings (install/user folders, profile help, PTY presets, **keypad scrollback help**, theme) · Connect (social links from `gui-links`) · Help (**in-app runbook** or **open in browser**, About)
- **Theme:** Settings → Light / Dark / Follow system (WPF-UI, persisted in `gui.local.json`).
- Embedded vibetty terminal preview — **display only**; voice uses VibeKeys + the vibetty server's configured ASR provider (e.g. Groq Whisper), not browser mic
- Embedded preview hides vibetty web chrome (mic, theme, nav) and **locks xterm to launched cols×rows** so a small PTY (e.g. 40×12) is not stretched across the WebView
- **PTY size presets** from JSON — shipped `config/pty-size-presets.json`; override `%LOCALAPPDATA%\VibeLaunch\pty-size-presets.local.json` (see `config/pty-size-presets.local.json.example`)
- PTY cols/rows sliders — **applied on Launch** via `mode con` before vibetty starts (post-launch console attach cannot shrink vibetty's ConPTY buffer). Log shows `pty geometry: NxM … ok`. Status bar shows `geom: NxM` and keypad readiness.
- **Keypad scrollback:** cols ≈35 for OLED legibility; **rows = scroll depth** (default 200). Tiny rows leave little history to scroll. GUI: Settings → Keypad scrollback help. Diagnostic preset: `cmd scroll test`.
- **VibeKeys Sync clamp:** while the keypad is connected, upstream vibetty forces width ≤ 35 cols on Sync — wide presets still apply to the PTY and web preview, but the OLED may look ~35-wide until upstream changes that behavior.
- Setup/Copy warn when no session or `keypadHost` does not match this PC's LAN IP
- VibeKeys install folder detected from `vibettyPath` in config (not hardcoded)
- Hide vibetty console after sized spawn (`mode con` → vibetty → hide console HWND)
- Toolbar: Copy keypad URL, Setup, Refresh

### PTY size presets (user-editable)

Shipped: [`config/pty-size-presets.json`](config/pty-size-presets.json)

Override (replaces list): copy [`config/pty-size-presets.local.json.example`](config/pty-size-presets.local.json.example) to:

`%LOCALAPPDATA%\VibeLaunch\pty-size-presets.local.json`

```json
[
  { "label": "VibeKeys (35x200)", "cols": 35, "rows": 200 },
  { "label": "Wide (80x40)", "cols": 80, "rows": 40 }
]
```

Click **Refresh** in the GUI after editing. Sliders still allow custom sizes between launches. See **Settings → Keypad scrollback help** for why cols vs rows matters.

### Help / social links (personalize before publish)

Copy [`config/gui-links.local.json.example`](config/gui-links.local.json.example) to:

`%LOCALAPPDATA%\VibeLaunch\gui-links.local.json`

```json
{
  "github": "https://github.com/your-org/your-repo",
  "youtube": "https://www.youtube.com/@yourchannel",
  "twitter": "https://x.com/yourhandle",
  "buyMeACoffee": "https://buymeacoffee.com/yourname",
  "linkedin": "https://www.linkedin.com/in/yourprofile"
}
```

Empty keys hide the matching Connect menu items. Shipped defaults in [`config/gui-links.json`](config/gui-links.json) cover the social links plus VibeKeys docs and runbook path.

### Rebuild

Close the running VibeLaunch window before rebuilding (same `dotnet build` path as above).

Then `.\vibelaunch-gui.ps1` (PowerShell) or `.\vibelaunch-gui.cmd` (CMD).

Settings persist in `%LOCALAPPDATA%\VibeLaunch\gui.local.json` (cols, rows, theme, hide console). GUI defaults in `config/defaults.json` → `gui` section.

### WinForms fallback

`gui/vibelaunch-gui.ps1` — no build step; captures CLI output; **Open browser** button; uses `--gui` launch flags.

---

## Publishing checklist

1. **Personal links:** copy [`config/gui-links.local.json.example`](config/gui-links.local.json.example) → `%LOCALAPPDATA%\VibeLaunch\gui-links.local.json` (GitHub, YouTube, X, Buy Me a Coffee, LinkedIn).
2. **Build GUI (Release):** see [Rebuild](#rebuild) above.
3. **WSL profile:** `setup-wsl-remote.ps1` (prompts for `wsl.user` + `keypadHost`) or edit `defaults.local.json` directly with port **3001**.
4. **Smoke test:** `vibelaunch preflight` (checks `wsl.user` is set, not a placeholder) → launch a preset → keypad connects → voice round-trip → GUI embed matches PTY size.
5. **Optional install:** `install.ps1` (Admin) → `C:\Program Files\VibeLaunch\`.
6. **No secrets in repo:** ASR keys live in `%USERPROFILE%\.vibetty\config.toml` only; `config/*.example` files should only contain placeholders (`<wsl-user>`, `<LAN-IP>`, `<windows-user>`), never a real value.

Stretch goals (not required for publish): mid-session preset hotswap, session parking — see [Roadmap](#roadmap).
