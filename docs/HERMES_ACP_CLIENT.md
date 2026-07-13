# Hermes ACP Client — drop-in coding-agent sessions

VibeLaunch turns a VibeKeys Max into a handheld coding Swiss-army knife by
putting every tool in one VibeKeys session. This document covers the piece that
lets **Hermes** itself drop *into* a live **Cursor / Claude Code / Codex / Gemini**
session — the same "sit inside the agent" experience OpenClaw's ACP harness
gave, but built natively on Hermes.

> **What problem this solves:** Hermes ships as an ACP *server* (`hermes acp`
> for IDEs) but not an ACP *client*. So you could not use Hermes to drive
> Cursor/Claude/Codex the way OpenClaw's `acpx` did. This tool fills that gap
> with zero external dependencies (Python stdlib only), mirroring Hermes's own
> bundled `agent/copilot_acp_client.py`.

## Why it matters for VibeLaunch

- The handheld can launch Hermes, then Hermes can **enter** a Cursor/Claude/Codex
  session on demand — all from the same keypad, same VibeKeys session.
- No API keys: each agent uses its own **subscription** (Cursor Pro / Claude Pro /
  ChatGPT Plus-Pro Codex).
- Structured, typed session (text chunks, file edits, permission requests) — not
  terminal screen-scraping.

## Upstream context (please boost)

This is a stopgap. The same capability is proposed in core Hermes as
[Hermes issue #5257](https://github.com/NousResearch/hermes-agent/issues/5257)
("Generalized ACP client for multi-agent CLI orchestration") — `hermes --provider
{agent}-acp` + a 14-agent registry. It is **open / P3 / needs-decision**.
If you want this upstream, **comment + 👍 on #5257** — community signal moves
it forward. A working reference fork exists at
`flowforgelab/hermes-agent@feat/acpx-plugin`.

When #5257 lands, retire this client and point VibeLaunch presets at the native
Hermes provider instead.

## Install the client

Canonical source in this repo: [`tools/hermes-acp-client.py`](../tools/hermes-acp-client.py).

Presets expect it at **`~/bin/hermes-acp-client.py`** inside WSL. Deploy with either:

```powershell
# After clone or install.ps1 — copies tools\ into WSL ~/bin
.\setup-wsl-remote.ps1 -WslUser <wsl-user> -KeypadHost <LAN-IP>
```

Or manually:

```bash
mkdir -p ~/bin
# From the Windows vibelaunch clone (adjust drive/path):
cp /mnt/c/path/to/vibelaunch/tools/hermes-acp-client.py ~/bin/
chmod +x ~/bin/hermes-acp-client.py
```

`install.ps1` also installs `tools\` under `C:\Program Files\VibeLaunch\tools\` so
you can copy from there into WSL.

## Usage

```bash
# One-shot prompt into a live Cursor ACP session
python3 ~/bin/hermes-acp-client.py send cursor "Add a CHANGELOG entry for v0.3" \
  --cwd /path/to/repo --approve

# Persistent drop-in (type prompts; Ctrl-D or 'exit' quits)
python3 ~/bin/hermes-acp-client.py shell cursor --cwd /path/to/repo --approve

# Other agents (launch command overridable via HERMES_ACP_{NAME}_COMMAND)
python3 ~/bin/hermes-acp-client.py shell claude  --cwd /path/to/repo --approve
python3 ~/bin/hermes-acp-client.py shell codex  --cwd /path/to/repo --approve
python3 ~/bin/hermes-acp-client.py shell gemini --cwd /path/to/repo --approve
```

| Flag | Meaning |
|------|---------|
| `--cwd PATH` | Working directory the agent may read/write (sandbox root). Required. |
| `--approve` | Auto-approve `session/request_permission` (recommended; mirrors `approve-all`). Without it, permission requests are cancelled. |

## How it works

1. Spawns the agent's ACP server as a subprocess over stdio (NDJSON, one
   JSON-RPC object per line).
2. Handshake: `initialize` → `session/new` → `session/prompt`.
3. The agent streams `session/update` events (`agent_message_chunk`,
   `agent_thought_chunk`); the client answers `session/request_permission`
   and serves `fs/read_text_file` / `fs/write_text_file` (sandboxed to `--cwd`).
4. `send` returns the collected assistant text; `shell` keeps the session open
   for multi-turn drop-in.

## Verified

| Agent | `send` | `shell` (file edit/read-back) | Notes |
|-------|--------|-------------------------------|-------|
| **Cursor** | ✅ | ✅ | End-to-end against `agent acp`; file created + read back through Cursor proves the permission/fs bridge. Auth = Cursor Pro. |
| **Claude Code** | ✅ | ✅ | Via `npx @agentclientprotocol/claude-agent-acp`; `send` returned `CLAUDE_ACP_OK`. Auth = Claude Pro. |
| **Codex** | ✅ | ✅ | Adapter + ACP `initialize`/`session/new` handshake verified; live `send` returns `CODEX_ACP_OK` after `codex login`. |
| **Gemini** | — | — | `gemini --acp` documented; Gemini CLI not required for VibeLaunch publish. |

Exercise:

```bash
python3 ~/bin/hermes-acp-client.py send cursor \
  "Reply with exactly: ACP_CLIENT_DROPIN_OK" --cwd /tmp --approve
```

## VibeLaunch presets

```cmd
vibelaunch hermes-acp-cursor --force     # drop into live Cursor  (verified)
vibelaunch hermes-acp-claude  --force     # drop into live Claude Code (verified)
vibelaunch hermes-acp-codex   --force     # drop into live Codex (verify codex login)
```

Each preset runs:

```bash
python3 ~/bin/hermes-acp-client.py shell <cursor|claude|codex> \
  --cwd {{workspaces.default-wsl}} --approve
```

Definitions: `config/presets.json`. Skill routes: `/vibekeys hermes-acp-cursor` (etc.).

## Agent launch commands

| Agent | Default command | Override env |
|-------|-----------------|--------------|
| `cursor` | `agent acp` | `HERMES_ACP_CURSOR_COMMAND` |
| `claude` | `npx @agentclientprotocol/claude-agent-acp` | `HERMES_ACP_CLAUDE_COMMAND` |
| `codex` | `npx @zed-industries/codex-acp` | `HERMES_ACP_CODEX_COMMAND` |
| `gemini` | `gemini --acp` | `HERMES_ACP_GEMINI_COMMAND` |
| *any* | `<name> acp` (fallback) | `HERMES_ACP_<NAME>_COMMAND` |

## Relationship to one-shot CLI wrappers

This ACP client is the **drop-in / interactive** counterpart to one-shot Hermes
CLI wrappers (`claude -p` / `codex exec` / `agent -p`). Use print-mode wrappers
for fire-and-forget delegation; use this client when you want to sit in the
session and steer it turn-by-turn — the handheld use case.

OpenClaw's separate path (`/acp spawn cursor` via `openclaw-cursor-workspace`)
is an ACP *harness* hosted by OpenClaw, not this Hermes client.
