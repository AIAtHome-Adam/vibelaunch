# OpenClaw ACP harness enablement (VibeLaunch)

This is the runbook for the **OpenClaw ACP harness** presets — not the Hermes ACP *client* drop-ins.

| Preset | Tokens | What it launches |
|--------|--------|------------------|
| `openclaw-cursor-workspace` | `openclaw cursor workspace` | Windows vibetty → WSL `openclaw tui --message '/acp spawn cursor …'` |
| `openclaw-codex-workspace` | `openclaw codex workspace` | Same path with harness id `codex` |

Related but **not** ACP harness presets: `openclaw-vk`, `openclaw-tui` (plain OpenClaw TUI). Hermes drop-ins live in [HERMES_ACP_CLIENT.md](HERMES_ACP_CLIENT.md).

Upstream: [ACP agents](https://docs.openclaw.ai/tools/acp-agents), [ACP setup](https://docs.openclaw.ai/tools/acp-agents-setup), [TUI CLI](https://docs.openclaw.ai/cli/tui).

---

## Topology (supported)

```text
Windows VibeLaunch / vibetty  (e.g. 0.0.0.0:3001)
        │
        ▼
  cmd.exe /c wsl.exe -u <wsl.user> bash -lic "…"
        │
        ▼
  WSL OpenClaw gateway  (loopback :18789) + acpx plugin
        │
        ▼
  /acp spawn <cursor|codex> --cwd <workspaces.default-wsl> --mode persistent
        │
        ▼
  External harness (Cursor agent acp, Codex ACP adapter, …)
```

**Supported:** WSL-hosted OpenClaw + ACPX on the gateway host (this machine's WSL).

**Not supported / expected limitation:** a native Windows-spawn OpenClaw companion. There is no Windows `openclaw` preset; do not treat "openclaw missing on Windows PATH" as a broken ACP preset.

VibeLaunch only starts/stops **Windows vibetty**. It does **not** start the OpenClaw gateway.

---

## Prerequisites

### VibeLaunch (Windows)

1. Install/production copy with `vibelaunch` on the persisted User PATH (`C:\Program Files\VibeLaunch`).
2. `vibetty.exe` present (default `C:\Program Files (x86)\Vibekeys\vibetty.exe`).
3. Local overrides in `%LOCALAPPDATA%\VibeLaunch\defaults.local.json` (or profile):

```json
{
  "wsl": { "enabled": true, "user": "<real-wsl-user>" },
  "workspaces": {
    "default": "C:\\Users\\<you>\\Documents\\Workspaces\\YourProject",
    "default-wsl": "/mnt/c/Users/<you>/Documents/Workspaces/YourProject"
  },
  "port": 3001
}
```

4. Workspace paths must exist. ACP presets inject **`workspaces.default-wsl`** into `/acp spawn … --cwd`.
5. `vibelaunch preflight` should report WSL available and `wsl.user` set.

### OpenClaw (WSL)

1. OpenClaw CLI installed in WSL; gateway running (`openclaw health` / port **18789** listening).
2. ACP enabled with backend `acpx`:

```bash
openclaw plugins install @openclaw/acpx   # once
openclaw config set plugins.entries.acpx.enabled true
openclaw config set acp.enabled true
openclaw config set acp.backend acpx
```

3. If `plugins.allow` is set, it **must** include `acpx` (restrictive allowlists otherwise hide the backend).
4. Allow harness ids you intend to use:

```bash
# example: cursor only
openclaw config set acp.allowedAgents '["cursor"]'

# example: cursor + codex
openclaw config set acp.allowedAgents '["cursor","codex"]'
```

5. Harness commands (override when local paths differ). Cursor on this host commonly uses `agent acp`:

```json
{
  "plugins": {
    "entries": {
      "acpx": {
        "enabled": true,
        "config": {
          "permissionMode": "approve-all",
          "nonInteractivePermissions": "deny",
          "probeAgent": "cursor",
          "agents": {
            "cursor": {
              "command": "/home/<user>/.local/bin/agent",
              "args": ["acp"]
            },
            "codex": {
              "command": "npx",
              "args": ["-y", "@zed-industries/codex-acp"]
            }
          }
        }
      }
    }
  }
}
```

OpenClaw embeds an ACPX **codex wrapper** that sets `CODEX_HOME` to `~/.openclaw/acpx/codex-home/` (not your normal `~/.codex`). After `codex login` in WSL, copy/sync `~/.codex/auth.json` into that wrapper home (mode `600`) or the spawn fails with **Authentication required** even when `codex login status` looks fine in the user shell.

Verified 2026-07-26 (GameHub): with `allowedAgents` including `codex`, wrapper auth synced, and gateway restarted, `/acp spawn codex --mode oneshot` returned `agent:codex:acp:…`. Cursor spawn remains the probe default.

6. Non-interactive permissions: schema allows only `deny` or `fail` (not `allow`). Prefer `permissionMode=approve-all` for coding harnesses. See upstream permission docs.
7. Restart the gateway after ACP/acpx / `allowedAgents` changes (`allowedAgents` is a restart-required key).
8. Target agent auth on the **WSL** host:

| Harness | Auth check (examples) |
|---------|------------------------|
| `cursor` | Cursor Agent CLI logged in (`agent` / `cursor-agent`); Pro entitlement for ACP |
| `codex` | `codex login status` in WSL **and** `~/.openclaw/acpx/codex-home/auth.json` present (wrapper CODEX_HOME). ChatGPT **credits** can extend past weekly plan limits; weekly bar at 0% does not mean Codex is dead if credits remain. Windows Codex login alone does not satisfy WSL/wrapper homes. |

---

## Enablement checklist

1. `openclaw health` → gateway ok; plugins list includes **acpx**.
2. In a TUI session (not `openclaw agent` webchat — slash commands need the TUI/native path):

```bash
openclaw tui --session acp-check --message '/acp doctor'
```

Expect: `configuredBackend: acpx`, `runtimeDoctor: ok`, `healthy: yes`, probe agent command path.

3. Dry-run VibeLaunch recipes:

```cmd
vibelaunch openclaw-cursor-workspace --dry-run
vibelaunch openclaw-codex-workspace --dry-run
```

Confirm cwd and:

`… vibetty … -- cmd.exe /c wsl.exe -u <user> bash -lic "openclaw tui --message '/acp spawn … --cwd <default-wsl> --mode persistent'"`

4. Launch (kills existing vibetty on the configured port):

```cmd
vibelaunch openclaw-cursor-workspace --force
```

5. Optional manual TUI proof of the same payload:

```bash
openclaw tui --message "/acp spawn cursor --cwd /mnt/c/.../YourProject --mode persistent"
```

Success looks like: `Spawned ACP session agent:cursor:acp:<uuid> (persistent, backend acpx)`.

---

## Parameters (preset contract)

| Piece | Source | Notes |
|-------|--------|-------|
| Platform | `presets.json` `platform: wsl` | Always WSL via `wsl.exe` |
| WSL user | `{{wsl.user}}` | Must be real; placeholder fails preflight |
| CWD for vibetty | `{{workspaces.default}}` | Windows path |
| CWD for ACP harness | `{{workspaces.default-wsl}}` | Injected into `/acp spawn --cwd` |
| Mode | `--mode persistent` | Keeps harness session; oneshot is for probes only |
| VibeLaunch `--force` | CLI flag | Kills vibetty tree only — **never** pass `--force` through to OpenClaw |
| OpenClaw `--message` | preset spawn | Delivers `/acp spawn …` after TUI connects |

---

## Error remediation

| Symptom / signal | Likely cause | Fix |
|------------------|--------------|-----|
| preflight: `wsl.user` missing / placeholder | Local defaults not set | Set `wsl.user` in `defaults.local.json`; re-run `setup-wsl-remote.ps1` if using that profile |
| vibetty exits; openclaw not found in WSL | OpenClaw not on WSL login PATH | Install OpenClaw in WSL; use `bash -lic` (presets already do) |
| TUI cannot connect / connection refused :18789 | Gateway down | Start gateway / `systemctl --user` unit; `openclaw health` |
| `/acp doctor` missing backend / unhealthy | acpx disabled or not allowlisted | Enable plugin; add `acpx` to `plugins.allow`; restart gateway |
| `ACP agent "codex" is not allowed by policy` | `acp.allowedAgents` omit `codex` | Add `codex` to allowlist **or** treat preset as config-blocked until you intentionally enable it |
| `ACP agent "cursor" is not allowed by policy` | Same for cursor | Add `cursor` to `acp.allowedAgents` |
| PermissionPromptUnavailableError / early ACP fail | Non-interactive permissions | Set `permissionMode=approve-all` or `nonInteractivePermissions=deny`; restart gateway |
| Codex harness starts then auth/401 | WSL Codex not logged in | `codex login` in WSL; Windows auth is separate |
| Cursor harness fails to start | Bad command path / no auth | Point `plugins.entries.acpx.config.agents.cursor` at real `agent`/`cursor-agent`; complete Cursor CLI login |
| vibetty log shows split argv (`"--message", "'/acp", "spawn"…`) | Spawn line broken outside VibeLaunch | Use `vibelaunch` (or `cmd.exe /c wsl … bash -lic "openclaw tui --message '…'"` as one string). Do not hand-split the message. |
| `openclaw agent --message '/acp …'` ignores slash | Agent CLI path is not native slash fast-path | Use `openclaw tui --message` or a real TUI/channel session |

---

## Validation notes (GameHub, 2026-07-26)

Sanitized evidence under the task review dir (not secrets):

| Check | Result |
|-------|--------|
| Gateway health | ok; **acpx** loaded |
| Config (sanitized) | `acp.enabled=true`, `backend=acpx`, `allowedAgents=["cursor"]` only; acpx `agents.cursor.command` → `~/.local/bin/agent acp` |
| `/acp doctor` via `openclaw tui --message` | **healthy**; probe agent cursor |
| `/acp spawn cursor … --mode persistent` via TUI | **ok** — spawned `agent:cursor:acp:<uuid>` |
| `/acp spawn codex …` via TUI | **blocked by policy** — `ACP agent "codex" is not allowed by policy` |
| WSL `codex login status` | **Not logged in** (secondary blocker even after allowlist) |
| `vibelaunch … --dry-run` for both ACP presets | **ok** — resolves WSL user, demo workspace, correct `cmd.exe /c wsl … bash -lic "openclaw tui --message '…'"` |
| Vibetty host of correct-shape cursor recipe | **ok** — process binds and stays up; vibetty file logs are server-side only (PTY content not in `vibetty_*.log`) |
| Windows-native OpenClaw ACP | **N/A** — unsupported topology |

**Classification**

- `openclaw-cursor-workspace`: **supported when local OpenClaw ACP is enabled** (verified on this host with cursor allowlisted + Cursor agent present).
- `openclaw-codex-workspace`: **not broken as a recipe**; **config-blocked** here until `codex` is added to `acp.allowedAgents` **and** WSL `codex login` succeeds. Prefer native OpenClaw `/codex` when you only need Codex chat control; this preset is the explicit ACP harness path.

Do not broaden `allowedAgents` or run `codex login` from automation without operator intent.
