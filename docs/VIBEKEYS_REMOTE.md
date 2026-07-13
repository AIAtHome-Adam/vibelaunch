# VibeKeys Remote Setup

This public runbook covers the VibeLaunch side of a VibeKeys Max remote terminal setup without machine-specific hostnames, usernames, LAN IPs, or API keys.

## What VibeLaunch Starts

VibeLaunch starts Windows `vibetty.exe`, binds it to a configured address and port, and then spawns one of the preset commands after `--`.

Common examples:

```powershell
vibelaunch codex --force
vibelaunch hermes --force
vibelaunch openclaw --force
vibelaunch claude --force
```

WSL examples use `wsl.exe -u {{wsl.user}} bash -lic "<command>"` through `config/presets.json`.

Hermes ACP drop-in (Cursor / Claude / Codex):

```powershell
vibelaunch hermes-acp-cursor --force
```

See [HERMES_ACP_CLIENT.md](HERMES_ACP_CLIENT.md).

## Profiles

| Profile | Port | Use |
|---------|------|-----|
| `standalone` | `3000` | Public default; Windows-native CLI sessions |
| `wsl-remote` | `3001` | Example WSL / remote-keypad profile |

Set the profile in `%LOCALAPPDATA%\VibeLaunch\defaults.local.json`, or run:

```powershell
.\setup-wsl-remote.ps1 -WslUser <wsl-user> -KeypadHost <LAN-IP>
```

That script also deploys `tools/hermes-acp-client.py` into WSL `~/bin/` when present.

The keypad WebSocket URL is:

```text
ws://<LAN-IP>:<port>/ws
```

Confirm with `vibelaunch status` (do not trust the vibetty footer if it shows `localhost` — that can be a display quirk while bind is `0.0.0.0`).

## Firewall Checklist

1. Allow inbound traffic to `vibetty.exe` on your chosen port (TCP).
2. Remove any inbound **Block** rule for `vibetty.exe`; on Windows, Block rules win over Allow rules.
3. Test from another device on the same network, not only from the host PC.
4. If the keypad never connects: `Get-NetFirewallRule` / Windows Defender Firewall UI — search for `vibetty` and delete Block entries.

## Voice / ASR

Voice on the keypad uses vibetty's **configured ASR provider** (for example Groq Whisper, or whichever provider you set in vibetty config). It is **not** the browser microphone in the GUI WebView.

- Put provider keys only in local vibetty config (e.g. `%USERPROFILE%\.vibetty\config.toml`).
- Never commit API keys to this repo.
- If transcription fails: check vibetty config, network reachability to the provider, and that the keypad WebSocket is connected.

## PTY Size And Scrolling

- `cols` controls terminal width. Around `35` columns works well for small OLED displays.
- `rows` controls scroll depth, not visible keypad lines. The shipped default is `35x200`.
- GUI slider changes apply on the next launch.
- If troubleshooting, show the vibetty console and resize it manually; vibetty will resync geometry.
- While the keypad is connected, upstream vibetty Sync may clamp width ≤ 35 cols on the OLED even if the PTY is wider.

## Codex / PATH tips

- If Codex exits immediately, the shell that launched vibetty may have a stale PATH. Open a **new** terminal or reinstall Codex so `codex` resolves.
- Codex ChatGPT token errors (`token_invalidated`) are account-side — run `codex login` again. Not a VibeLaunch bug.

## Hermes ACP troubleshooting

| Symptom | Check |
|---------|-------|
| `python3: can't open file '.../hermes-acp-client.py'` | Run `setup-wsl-remote.ps1` or copy `tools/hermes-acp-client.py` → WSL `~/bin/` |
| Cursor ACP fails auth | `agent login` (Cursor Pro) |
| Claude ACP fails | Node + `npx @agentclientprotocol/claude-agent-acp` + Claude Pro |
| Codex ACP 401 | `codex login` in WSL |
| Want native Hermes ACP | Track / comment on [Hermes #5257](https://github.com/NousResearch/hermes-agent/issues/5257) |

## Manual vibetty (escape hatch)

If you need to bypass VibeLaunch temporarily:

```powershell
& "<path-to-vibetty.exe>" --bind-addr 0.0.0.0:<port> -- <spawn command...>
```

Prefer `vibelaunch run --spawn '...'` so config bind/port still apply.

## Secrets

Do not commit real ASR keys or agent credentials. Keep them in local tool config files such as `%USERPROFILE%\.vibetty\config.toml`, WSL `.env` files, or your credential manager.

Example overlays (`config/*.local.json.example`) must only contain placeholders (`<wsl-user>`, `<LAN-IP>`, `<windows-user>`).
