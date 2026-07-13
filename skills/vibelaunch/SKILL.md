---
name: vibelaunch
description: >
  Legacy alias for VibeKeys / vibetty session control on Windows. Triggers:
  vibelaunch, switch keypad, stop vibetty, launch codex on keypad, launch
  hermes on keypad, launch openclaw on keypad. Superseded by
  skills/vibekeys — deploy that one for new installs; this file stays only
  for backward-compat trigger matching.
metadata: {"openclaw":{"emoji":"⌨️","requires":{"bins":["powershell"]}}}
---

# VibeLaunch (legacy alias)

**This skill is a thin alias.** All command tables, reply-format rules, and boundaries now live in one place: [`skills/vibekeys/SKILL.md`](../vibekeys/SKILL.md). Read that file for the actual routing logic — this one exists only so old deploys that reference the `vibelaunch` skill name (instead of `vibekeys`) keep matching the same triggers.

**If you are setting this up fresh, deploy [`skills/vibekeys/SKILL.md`](../vibekeys/SKILL.md) instead** and skip this file entirely.

Deterministic control of the Windows **vibetty** side channel — **no improvising**. Always invoke the installed `vibelaunch` CLI; never hand-build vibetty command lines.

**From WSL (Hermes or OpenClaw):**

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:/Program Files/VibeLaunch/vibelaunch.ps1" <subcommand>
```

Dev layout: clone path `...\vibelaunch\vibelaunch.ps1`.

Use the **exec** tool only. Reply with CLI output (trim to 3500 chars if needed). Compact reply format: see [vibekeys skill](../vibekeys/SKILL.md#reply-format-compact).

## Command mapping

Same commands, same tables — see [`skills/vibekeys/SKILL.md`](../vibekeys/SKILL.md#slash-commands) and [natural language table](../vibekeys/SKILL.md#natural-language). This file does not duplicate them to avoid the two skills drifting out of sync.

## Important boundaries

Full list: [`skills/vibekeys/SKILL.md#boundaries`](../vibekeys/SKILL.md#boundaries). Headline reminders:

- **VibeLaunch** kills/restarts **Windows vibetty only** — never WSL systemd gateways (OpenClaw, Hermes gateway).
- **`--force`** is VibeLaunch-only (kill/switch). Never pass to spawned CLIs.
- **Port profile:** standalone default is `:3000`; WSL-remote example uses `:3001`.

Full docs: repo `README.md`, [docs/VIBEKEYS_REMOTE.md](../../docs/VIBEKEYS_REMOTE.md), [docs/VIBEKEYS_AGENT_SKILLS.md](../../docs/VIBEKEYS_AGENT_SKILLS.md), [docs/HERMES_ACP_CLIENT.md](../../docs/HERMES_ACP_CLIENT.md).

**Deploy to Hermes workspace (legacy):** copy to `~/.hermes/skills/productivity/vibelaunch/SKILL.md`. **Prefer deploying `vibekeys` instead** for new setups.
