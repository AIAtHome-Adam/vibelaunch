# VibeKeys Agent Skills

VibeLaunch can be controlled by agent skills, slash commands, or natural-language routing in a chat agent. Skill files ship under [`skills/`](../skills/) and are optional for the VibeLaunch CLI or GUI.

## Session control (`vibekeys`)

A session-control skill should call the Windows `vibelaunch` CLI and never hand-build `vibetty` command lines. Canonical skill: [`skills/vibekeys/SKILL.md`](../skills/vibekeys/SKILL.md). Legacy alias: [`skills/vibelaunch/SKILL.md`](../skills/vibelaunch/SKILL.md).

| Request | VibeLaunch command |
|---------|--------------------|
| `/vibekeys status` | `vibelaunch status` |
| `/vibekeys list` | `vibelaunch list` |
| `/vibekeys codex` | `vibelaunch codex-workspace --force` |
| `/vibekeys hermes` | `vibelaunch hermes --force` |
| `/vibekeys hermes-wsl` | `vibelaunch hermes-vk-wsl --force` |
| `/vibekeys hermes-win` | `vibelaunch hermes-vk-win --force` |
| `/vibekeys openclaw` | `vibelaunch openclaw --force` |
| `/vibekeys claude` | `vibelaunch claude --force` |
| `/vibekeys cursor` | `vibelaunch openclaw-cursor-workspace --force` |
| `/vibekeys codex-acp` | `vibelaunch openclaw-codex-workspace --force` |
| `/vibekeys hermes-acp-cursor` | `vibelaunch hermes-acp-cursor --force` |
| `/vibekeys hermes-acp-claude` | `vibelaunch hermes-acp-claude --force` |
| `/vibekeys hermes-acp-codex` | `vibelaunch hermes-acp-codex --force` |
| `/vibekeys stop` | `vibelaunch stop --force` |

### ACP paths (two different stacks)

| Path | Presets | Docs |
|------|---------|------|
| **Hermes ACP client** (sit inside Cursor/Claude/Codex) | `hermes-acp-cursor`, `hermes-acp-claude`, `hermes-acp-codex` | [HERMES_ACP_CLIENT.md](HERMES_ACP_CLIENT.md), upstream [#5257](https://github.com/NousResearch/hermes-agent/issues/5257) |
| **OpenClaw ACP harness** | `openclaw-cursor-workspace`, `openclaw-codex-workspace` | OpenClaw ACP docs; requires local harness config |

## Keypad UX skills

| Skill | When |
|-------|------|
| [`vibekeys-hermes`](../skills/vibekeys-hermes/SKILL.md) | Hermes chat with `--skills vibekeys-hermes` / VibeKeys session |
| [`vibekeys-openclaw`](../skills/vibekeys-openclaw/SKILL.md) | OpenClaw TUI session key `vibekeys` |

For small displays, keep agent responses compact:

- Prefer short lines (~32–35 chars).
- Ask clarifying questions before long multi-step work.
- Use numbered choices when asking the operator to pick an option.
- Avoid dumping large logs or tables into the keypad session.

## Boundary

VibeLaunch manages the Windows `vibetty` process. It does not start or stop OpenClaw, Hermes, model gateways, Discord bots, or other background services.
