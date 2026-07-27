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

This remains a stopgap, but the upstream lineage has changed:

- [Issue #5257](https://github.com/NousResearch/hermes-agent/issues/5257) is the
  original **design issue**: "Generalized ACP client for multi-agent CLI
  orchestration."
- [PR #5258](https://github.com/NousResearch/hermes-agent/pull/5258) was the
  original 14-agent implementation. It was closed as a draft; its old fork
  predates major Hermes refactors and is effectively superseded.
- [PR #68222](https://github.com/NousResearch/hermes-agent/pull/68222) is the
  **active successor** rebased onto modern Hermes. As checked **2026-07-25**, it
  is open, non-draft, `P4` / `needs-decision`, supports Claude, Codex, Gemini,
  Qwen, and Copilot, and routes Hermes approval policies. Its known gap is that
  Hermes-configured MCP servers are not yet forwarded into spawned ACP sessions.
- [PR #32401](https://github.com/NousResearch/hermes-agent/pull/32401) is the
  larger architectural alternative: a native `api_mode: acp_client` transport.
  The Claude-only [PR #68050](https://github.com/NousResearch/hermes-agent/pull/68050)
  was closed in favor of #68222.

If you want native support, **comment + 👍 on #5257 and follow/boost #68222**.
The accurate shorthand is: **#5257 is the design issue; #5258 was the original
implementation; #68222 is the active successor.** Keep this client until a
current upstream implementation lands and covers VibeLaunch's session,
approval, MCP-forwarding, and provider-integration needs.

### Buzz connection

[Buzz PR #2773](https://github.com/block/buzz/pull/2773) bundles Hermes and
OpenClaw as ACP harness presets. It does not directly mention #5257/#5258/#68222,
but it strongly validates ACP as the shared harness boundary. The directions are
complementary: Buzz hosts/drives Hermes and other harnesses, while #68222 would
let Hermes itself drive Claude/Codex/Gemini/Qwen/Copilot outside Buzz.

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

**Installed-copy workspace:** after `install.ps1`, set real paths in
`%LOCALAPPDATA%\VibeLaunch\defaults.local.json` (`workspaces.default` +
`workspaces.default-wsl`). Without that overlay the shipped
`<windows-user>` placeholders stay unresolved on the Program Files install
and ACP sandbox cwd is wrong. Repo checkouts auto-derive a workspace from
the clone location.

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
