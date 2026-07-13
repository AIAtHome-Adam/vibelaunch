---
name: vibekeys-openclaw
description: >
  VibeKeys Max compact TUI mode for OpenClaw. Applies when the active
  session key is `vibekeys` (set via `openclaw tui --session vibekeys`,
  VibeLaunch's `openclaw-vk` preset, or a vibekeys launch wrapper). Short
  lines, clarify-first, numbered options for a 35x10 OLED + voice. Not for
  Discord/Signal — use the vibekeys skill for session switch.
metadata: {"openclaw":{"emoji":"⌨️"}}
---

# VibeKeys display mode (OpenClaw)

You are in a **VibeKeys keypad session** — ~**35 columns × 10 rows** on the OLED, voice input, Down-key navigation. Optimize every reply for that surface. Mirrors [`vibekeys-hermes`](../vibekeys-hermes/SKILL.md)'s conventions, adapted for the OpenClaw TUI.

**Detect context:** the session key is **`vibekeys`** — reliable signal (same key the launcher and preset use). `OPENCLAW_VIBEKEYS_SESSION=1` is a client-side hint only; prefer session key if visible in context.

**Session switching** is **not** this skill — the operator uses VibeLaunch / the `vibekeys` skill from another channel, or restarts vibetty manually. This skill only changes *how* you write inside an already-open `vibekeys` TUI session.

OpenClaw **ACP harness** presets (`openclaw-cursor-workspace`, `openclaw-codex-workspace`) are separate from Hermes ACP client presets — see [HERMES_ACP_CLIENT.md](../../docs/HERMES_ACP_CLIENT.md) for the Hermes path.

---

## Response rules (mandatory)

| Rule | Do |
|------|-----|
| **Line width** | Hard-wrap near **32–35 chars**; never rely on terminal soft-wrap |
| **Height** | **≤5 lines** of agent text before waiting for user (prompt + status eat rows) |
| **Clarify-first** | If intent is ambiguous, ask **one** short question — do not start tools yet |
| **Options** | Offer **2–3 numbered choices** (`1.` `2.` `3.`) — user moves with **Down** on keypad |
| **No tables** | No markdown tables, wide code blocks, or ASCII art |
| **Code** | One-liner or "say expand" — full patch on request only |
| **Tool output** | Summarize in ≤3 lines; never dump raw logs on keypad |
| **Progress** | Short status: `Checking…` / `Done: …` — no spinner walls |
| **Doctor/plugin noise** | Do not echo OpenClaw's own startup warnings back to the user — they're launch-wrapper noise, not agent output |

---

## Voice + keypad interaction

- User speaks; vibetty injects transcription + Enter. Parse natural phrasing, not only slash commands.
- Prefer **action verbs** in confirmations: `✓ Saved` not `The file has been successfully saved to disk`.
- For destructive actions: one-line confirm (`Delete X? 1 yes 2 no`).
- Remind exit when nested: `Say /exit or voice "exit" to leave this tool`.

---

## When user asks to switch agent on keypad

You **cannot** restart vibetty from inside the OpenClaw TUI reliably — same limitation as Hermes. Reply:

```
Keypad switch: use Discord/Signal
"vibekeys codex" or /vibekeys codex
Or VibeLaunch GUI on PC.
```

Do not invent `powershell` or vibetty commands unless exec to Windows is explicitly available **and** documented for this session.

---

## Examples

**Good (clarify-first):**

```
Which repo?
1 example-workspace
2 notebooks
3 other
```

**Good (result):**

```
✓ Task added to kanban
#42 Fix keypad doc
```

**Bad (too wide/tall):**

```
I've analyzed your request and found several possible
approaches we could take including modifying the config
file or using the CLI tool with various flags such as...
```

---

## Deploy

| Location | Path |
|----------|------|
| Repo (canonical) | `skills/vibekeys-openclaw/SKILL.md` |
| OpenClaw | Copy to workspace `skills/` — restart gateway; same deploy path as [`skills/vibelaunch/`](../vibelaunch/SKILL.md) |
| Launch | Use `openclaw-vk` preset (`openclaw tui --session vibekeys`) |

Full scope: [docs/VIBEKEYS_AGENT_SKILLS.md](../../docs/VIBEKEYS_AGENT_SKILLS.md).
