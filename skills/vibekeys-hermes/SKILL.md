---
name: vibekeys-hermes
description: >
  VibeKeys Max compact TUI mode for Hermes. Auto-loads when HERMES_VIBEKEYS_SESSION=1
  or via hermes chat --skills vibekeys-hermes. Short lines, clarify-first, numbered options
  for 35x10 OLED + voice. Not for Discord/Signal — use vibekeys skill for session switch.
metadata: {"hermes":{"emoji":"⌨️"}}
---

# VibeKeys display mode (Hermes)

You are in a **VibeKeys keypad session** — ~**35 columns × 10 rows** on the OLED, voice input, Down-key navigation. Optimize every reply for that surface.

**Detect context:** `HERMES_VIBEKEYS_SESSION=1` in the environment (set by Hermes VibeKeys launch wrappers / presets).

**Session switching** is **not** this skill — the operator uses VibeLaunch / `/vibekeys` from another channel, or restarts vibetty manually.

For **Hermes → Cursor/Claude/Codex drop-in** (ACP client), use VibeLaunch presets `hermes-acp-cursor` / `hermes-acp-claude` / `hermes-acp-codex` or `/vibekeys hermes-acp-*`. See [HERMES_ACP_CLIENT.md](../../docs/HERMES_ACP_CLIENT.md). Upstream: [#5257](https://github.com/NousResearch/hermes-agent/issues/5257) is the design issue; [#68222](https://github.com/NousResearch/hermes-agent/pull/68222) is the active successor.

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

---

## Voice + keypad interaction

- User speaks; vibetty injects transcription + Enter. Parse natural phrasing, not only slash commands.
- Prefer **action verbs** in confirmations: `✓ Saved` not `The file has been successfully saved to disk`.
- For destructive actions: one-line confirm (`Delete X? 1 yes 2 no`).
- Remind exit when nested: `Say /exit or voice "exit" to leave codex`.

---

## When user asks to switch agent on keypad

You **cannot** restart vibetty from inside Hermes TUI reliably. Reply:

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
| Repo (canonical) | `skills/vibekeys-hermes/SKILL.md` |
| Hermes | `~/.hermes/skills/vibekeys-hermes/SKILL.md` or hub install |
| Auto-load | `hermes chat --skills vibekeys-hermes` via launcher |

Full scope: [docs/VIBEKEYS_AGENT_SKILLS.md](../../docs/VIBEKEYS_AGENT_SKILLS.md).
