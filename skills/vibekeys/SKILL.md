---
name: vibekeys
description: >
  VibeKeys Max session control from agent channels. Triggers: /vibekeys,
  /vibekeys codex, /vibekeys hermes, /vibekeys openclaw, /vibekeys status,
  /vibekeys stop, /vibekeys hermes-acp-cursor, switch keypad, launch codex on
  keypad, vibekeys session, start vibekeys. Delegates to the vibelaunch CLI.
metadata: {"openclaw":{"emoji":"⌨️","requires":{"bins":["powershell"]}},"hermes":{"emoji":"⌨️","requires":{"bins":["powershell"]}}}
---

# VibeKeys (`/vibekeys`)

**Canonical, publication-facing** skill for switching the handheld keypad session from Discord, Signal, Hermes, or OpenClaw. Always runs the installed **`vibelaunch`** CLI on Windows — never hand-build vibetty command lines.

This is the single source of truth for session-control triggers and command tables. [`skills/vibelaunch/SKILL.md`](../vibelaunch/SKILL.md) is kept only as a **thin legacy alias** for deploys that still reference the old skill name — it points back here rather than duplicating these tables.

**From WSL:**

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:/Program Files/VibeLaunch/vibelaunch.ps1" <subcommand>
```

Dev layout: clone path `...\vibelaunch\vibelaunch.ps1`.

Use **exec** only. Reply with trimmed CLI output.

---

## Slash commands

| Command | Action |
|---------|--------|
| `/vibekeys` | `status` |
| `/vibekeys status` | `status` |
| `/vibekeys list` | `list` |
| `/vibekeys preflight` | `preflight` |
| `/vibekeys codex` | `codex-workspace --force` |
| `/vibekeys hermes` | `hermes-vk --force` (auto WSL or Windows) |
| `/vibekeys hermes-wsl` | `hermes-vk-wsl --force` |
| `/vibekeys hermes-win` | `hermes-vk-win --force` |
| `/vibekeys openclaw` | `openclaw --force` |
| `/vibekeys claude` | `claude --force` |
| `/vibekeys stop` | `stop --force` |
| `/vibekeys cursor` | `openclaw-cursor-workspace --force` *(OpenClaw ACP harness; local config required)* |
| `/vibekeys codex-acp` | `openclaw-codex-workspace --force` *(OpenClaw ACP harness; local config required)* |
| `/vibekeys hermes-acp-cursor` | `hermes-acp-cursor --force` *(Hermes ACP client → Cursor)* |
| `/vibekeys hermes-acp-claude` | `hermes-acp-claude --force` *(Hermes ACP client → Claude Code)* |
| `/vibekeys hermes-acp-codex` | `hermes-acp-codex --force` *(Hermes ACP client → Codex)* |

---

## Natural language

| User says | Command |
|-----------|---------|
| switch keypad to codex / launch codex on vibekeys | `codex-workspace --force` |
| switch to hermes on keypad | `hermes-vk --force` |
| hermes on wsl / force wsl hermes | `hermes-vk-wsl --force` |
| hermes on windows / native hermes | `hermes-vk-win --force` |
| openclaw on vibekeys / vibekeys session | `openclaw --force` |
| openclaw main session (debug) | `openclaw main --force` |
| drop into cursor via hermes / hermes acp cursor | `hermes-acp-cursor --force` |
| hermes into claude / hermes acp claude | `hermes-acp-claude --force` |
| hermes into codex / hermes acp codex | `hermes-acp-codex --force` |
| what's on the keypad | `status` |
| stop vibekeys / stop keypad session | `stop --force` |
| check vibekeys / diagnose keypad | `preflight` |
| list vibekeys presets | `list` |

Token-style (CLI parity): `hermes`, `hermes wsl`, `hermes windows`, `openclaw`, `openclaw main`, `codex`, `codex workspace`, `hermes acp cursor`, `openclaw cursor workspace`.

---

## Reply format (compact)

Lead with outcome, then details — readable on phone **and** if pasted to keypad:

```
✓ Switched to Hermes (hermes-vk)
Port 3001 · ws://<LAN-IP>:3001/ws
Keypad: reconnect WebSocket if needed.
```

- Trim to **≤15 lines** / **3500 chars**
- On success: preset name + keypad URL from `status`
- On failure: one-line cause + pointer to [VIBEKEYS_REMOTE.md](../../docs/VIBEKEYS_REMOTE.md) (firewall Block rule, stale Codex PATH, wrong port)

---

## Boundaries

- **VibeLaunch** = Windows vibetty only — never restart WSL gateways.
- **`--force`** is VibeLaunch-only — never pass to OpenClaw/Hermes/Codex CLIs.
- **In-session UX** on the keypad (short lines) = [`vibekeys-hermes`](../vibekeys-hermes/SKILL.md) / [`vibekeys-openclaw`](../vibekeys-openclaw/SKILL.md) — separate skills.
- WSL-remote example profile uses port **3001**; standalone default **3000**.
- OpenClaw ACP presets (`openclaw-cursor-workspace`, `openclaw-codex-workspace`) need local ACP harness config.
- Hermes ACP presets need `~/bin/hermes-acp-client.py` (see [HERMES_ACP_CLIENT.md](../../docs/HERMES_ACP_CLIENT.md)). Upstream: [#5257](https://github.com/NousResearch/hermes-agent/issues/5257) is the design issue; [#68222](https://github.com/NousResearch/hermes-agent/pull/68222) is the active successor.

Full roadmap: [docs/VIBEKEYS_AGENT_SKILLS.md](../../docs/VIBEKEYS_AGENT_SKILLS.md).
