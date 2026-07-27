# VibeLaunch preset test tracker (filming walkthrough)

Concise on-camera checklist for the **canonical GitHub preset set**. One row per preset. Distinguishes **live-verified**, **recipe-only**, **host/prereq**, and **intentional topology limitation** (not broken).

| Field | Meaning |
|-------|---------|
| **Status** | Camera-facing outcome label (see legend) |
| **Vibetty** | Launch-through-vibetty result when known |
| **Evidence** | Parent card / artifact path (traceable) |

## Snapshot

| Item | Value |
|------|--------|
| Tracker date | 2026-07-26 |
| Source of truth | GitHub `main` @ **`5aabb5b`** (`docs+fix: OpenClaw ACP runbook, preset help clarity, GUI link repair`) |
| Clean clone | `C:\Users\ITGAdmin\Documents\Workspaces\vibelaunch-clean` |
| Production install | `C:\Program Files\VibeLaunch` (may lag GitHub until reinstall/copy) |
| vibetty | `C:\Program Files (x86)\Vibekeys\vibetty.exe` (not on PATH) |
| CLI | `C:\Program Files\VibeLaunch\vibelaunch.ps1` or `.cmd` |
| Profile / port | gamehub / **3001** (`%LOCALAPPDATA%\VibeLaunch\defaults.local.json`) |
| Workspace | `C:\Users\ITGAdmin\Documents\Workspaces\VibeLaunch-Demo` ↔ `/mnt/c/Users/ITGAdmin/Documents/Workspaces/VibeLaunch-Demo` |
| WSL user | `itgadmin` |
| Canonical preset count | **17** (`config/presets.json`) |
| Dirty staging tree | `Agent-Framework\vibelaunch` — read-only; do not film from it |

### Status legend

| Label | Use when |
|-------|----------|
| **PASS** | Live Vibetty and/or behavioral proof succeeded on this host |
| **PASS*** | Live proof after host enablement (allowlist, auth, credits) — preset recipe OK |
| **RECIPE OK** | Dry-run / recipe / notes verified; full agent session not re-proven this pass |
| **HOST PREREQ** | Launch path OK; needs operator auth/config (not a broken preset) |
| **EXPECTED LIMIT** | Intentional route under WSL-first topology (Windows-only Hermes when live stack is WSL) — **not a defect** |
| **DIAG** | Diagnostic only (not an agent) |

### Classification rules (say on camera if needed)

- **Broken preset** = recipe wrong, wrong spawn, or VibeLaunch fails with correct host setup.
- **Not broken** = missing agent login, allowlist, gateway down, Windows Hermes not installed, or intentional Windows-only route when you only run Hermes in WSL.
- Prefer **`--force`** when switching presets on the same port.
- WSL cannot curl Windows vibetty on `127.0.0.1` — use Windows browser / `vibelaunch status`.

---

## Suggested filming order

1. **Preflight cold open** — `vibelaunch preflight` + `vibelaunch list` (notes legible).
2. **cmd-scroll-test** — prove PTY/scroll without agent risk.
3. **Windows agents** — `claude` → optional `claude-resume` → `codex-workspace` (or `codex`).
4. **Hermes WSL path** — `hermes-vk-wsl` (or `hermes-vk` auto) → optional model pin `hermes-codex-workspace`.
5. **OpenClaw TUI** — `openclaw-vk` (keypad session) → skip or briefly show `openclaw-tui` (main can spam).
6. **Hermes ACP drop-ins** — `hermes-acp-cursor` → `hermes-acp-claude` → `hermes-acp-codex` (credits/login).
7. **OpenClaw ACP harness** — `openclaw-cursor-workspace` → `openclaw-codex-workspace`.
8. **Optional contrast** — `hermes-vk-win` / `hermes-codex-workspace-win` as **EXPECTED LIMIT** if Windows Hermes is not provisioned (say so; do not call broken).

Cutaways: GUI embed, keypad WS URL from `status`, `docs/OPENCLAW_ACP.md` / `docs/HERMES_ACP_CLIENT.md` if narrating enablement.

---

## Host checklist (before roll)

| Check | Expected |
|-------|----------|
| vibetty path | Exists at Vibekeys install |
| Port 3001 | Free, or use `--force` |
| `wsl.user` | Real user (not placeholder) |
| `workspaces.default` + `default-wsl` | Real demo paths (not `C:\Program Files`) |
| OpenClaw gateway | Up (often `:18789`) for OpenClaw presets |
| `acp.allowedAgents` | Includes agents you will film (`cursor`, `codex`) |
| Codex | WSL `codex login` + credits/overage if weekly bar is 0 |
| Hermes ACP client | `~/bin/hermes-acp-client.py` matches `tools/hermes-acp-client.py` |
| Install vs GitHub | PF tree may predate `5aabb5b` notes/docs — film clone or reinstall if copy must match |

---

## Master matrix (all 17)

| # | Preset | Purpose | Host / topology | Required setup | Vibetty / live result | Limitation or error | Status | Remediation | Demo cue | Evidence |
|---|--------|---------|-----------------|----------------|----------------------|---------------------|--------|-------------|----------|----------|
| 1 | `claude` | Fresh Windows Claude Code | Windows-native @ `workspaces.default` | `claude` on PATH + signed in | Not re-proven live this cycle | — | **RECIPE OK** | Install Claude Code / fresh shell if missing | “Windows Claude in the demo workspace.” | Inventory t_d1c7db42; notes/dry-run t_16c852c3 |
| 2 | `claude-resume` | Resume last Claude + skip tool prompts | Windows-native | Prior Claude session; same PATH | Not re-proven live this cycle | Ships **`-c` and `--dangerously-skip-permissions`** | **RECIPE OK** | Nothing to resume → use `claude` first; override args in `presets.local.json` to keep prompts | Call out both flags on camera | t_16c852c3 (flag accuracy fix shipped `5aabb5b`) |
| 3 | `codex` | Windows Codex TUI at config `cwd` | Windows-native @ defaults `cwd` | `codex` on PATH + auth | Not re-proven live this cycle | Weekly quota may be 0; credits can still work | **RECIPE OK** | Instant exit → PATH/preflight; auth/credits → `codex login` | Contrast with workspace preset | t_d1c7db42; credits note t_65a3dcb4 reproof |
| 4 | `codex-workspace` | Windows Codex in demo workspace | Windows-native @ `workspaces.default` | Path exists + `codex` | Not re-proven live this cycle | Same auth/credits as `codex` | **RECIPE OK** | Fix `workspaces.default` if cwd wrong | Preferred Windows Codex shot | t_d1c7db42; t_16c852c3 |
| 5 | `cmd-scroll-test` | cmd.exe scrollback diagnostic | Windows-native | None beyond vibetty | Not re-proven live this cycle | Not an agent | **DIAG** / **RECIPE OK** | — | `for /L %i in (1,1,100) do @echo line %i` then scroll | t_d1c7db42; t_16c852c3 |
| 6 | `hermes-vk` | Hermes chat + vibekeys-hermes (auto host) | **auto**: WSL if enabled + hermes in WSL, else Windows | `wsl.user` / WSL hermes **or** Windows hermes | Not re-proven live this cycle | Windows fallback fails if only WSL Hermes exists | **RECIPE OK** (WSL branch expected) | Override: `vibelaunch hermes wsl` \| `hermes windows` | “Auto picks WSL on this machine.” | t_d1c7db42 topology **conditional** |
| 7 | `hermes-vk-wsl` | Force WSL Hermes + vibekeys | WSL via `wsl.exe` | `wsl.user`, hermes in distro | Not re-proven live this cycle | — | **RECIPE OK** | setup-wsl-remote / install hermes in WSL | Primary Hermes keypad route | t_d1c7db42 **expected_compatible** |
| 8 | `hermes-vk-win` | Force **Windows** Hermes only | Windows-native (no WSL) | Separate Windows hermes + auth | Not expected to match WSL-only stack | Live Hermes often WSL-only | **EXPECTED LIMIT** | Use `hermes-vk-wsl` / `hermes-vk`; or install Windows Hermes | “Intentional Windows route — not broken if we only run WSL.” | t_d1c7db42 **expected_limitation** |
| 9 | `hermes-codex-workspace` | WSL Hermes pinned `-m openai-codex/gpt-5.4` | WSL | WSL hermes + Codex provider auth | Model path later re-proved under credits (`CODEX_CREDIT_HERMES_OK`) — full vibetty session not re-scored | Model pin may differ from current fleet default | **RECIPE OK** / host model auth | `/model` or presets.local; hermes auth | Show model pin in spawn | t_d1c7db42; credits t_65a3dcb4 reproof |
| 10 | `hermes-codex-workspace-win` | Same model pin on Windows Hermes | Windows-native | Windows hermes + Windows Codex auth | — | Same as other Win Hermes | **EXPECTED LIMIT** | Prefer WSL preset when stack is WSL | Optional contrast only | t_d1c7db42 **expected_limitation** |
| 11 | `openclaw-vk` | OpenClaw TUI `--session vibekeys` | WSL-only | gateway up, openclaw in WSL, `wsl.user` | Not re-proven live this cycle | Connection refused → gateway | **RECIPE OK** | Start gateway (often `:18789`) | Best OpenClaw keypad session (less heartbeat spam) | t_d1c7db42; notes t_16c852c3 |
| 12 | `openclaw-tui` | OpenClaw main session | WSL-only | Same as openclaw-vk | Not re-proven live this cycle | Heartbeat/status noise on small screens | **RECIPE OK** | Prefer `openclaw-vk` for film | Brief “main vs vibekeys session” | t_d1c7db42 |
| 13 | `openclaw-cursor-workspace` | OpenClaw ACP harness → Cursor | WSL; TUI `--message '/acp spawn cursor…'` | gateway, acpx, `cursor` allowlisted, agent on PATH, `default-wsl` | **PASS** — Vibetty launch + spawn `agent:cursor:acp:*` | Needs local ACP enablement (documented) | **PASS** | See `docs/OPENCLAW_ACP.md` | “Harness path, not Hermes client.” | t_65a3dcb4; t_938cf5d4; `review-artifacts/t_65a3dcb4-openclaw-acp-validation.md` |
| 14 | `openclaw-codex-workspace` | OpenClaw ACP harness → Codex | WSL; spawn id `codex` | allowlist **codex**, acpx codex agent, auth in acpx `CODEX_HOME` | Early: policy deny + auth; **later PASS** spawn `agent:codex:acp:c07dc8cb-…` | Was config-blocked, not bad recipe | **PASS*** | allowlist + sync auth into `~/.openclaw/acpx/codex-home` | Narrate enablement then spawn success | t_65a3dcb4 + `t_65a3dcb4-codex-reproof-2026-07-26.md` |
| 15 | `hermes-acp-cursor` | Hermes ACP *client* → Cursor shell | WSL client drop-in | python3, client script, Cursor agent auth | **PASS** launch + send `ACP_CLIENT_DROPIN_OK`; multi-turn OK | Permission/extension compliance beyond basic session is out of scope | **PASS** | Deploy client; `agent` login | Hero drop-in shot | t_2449e672; t_938cf5d4; `hermes-acp-preset-validation.md` |
| 16 | `hermes-acp-claude` | Hermes ACP *client* → Claude ACP | WSL | Node/npx, Claude auth, client script | **PASS** launch + send `CLAUDE_ACP_OK` | — | **PASS** | `claude login` / Node if missing | Second ACP hero | t_2449e672 |
| 17 | `hermes-acp-codex` | Hermes ACP *client* → Codex ACP | WSL | Node, `codex login`, client script | Launch OK; early send **Authentication required**; **later** `HERMES_ACP_CODEX_OK` | Auth/credits — not recipe defect | **PASS*** | `codex login` in WSL; credits if weekly exhausted | Show failure then fix **or** start post-login | t_2449e672; reproof t_65a3dcb4 |

---

## Per-preset cards (camera detail)

### 1. `claude` — Claude Code

| | |
|--|--|
| **Purpose** | Fresh Windows Claude Code in demo workspace |
| **Topology** | native_windows_scope |
| **Setup** | Claude Code on Windows PATH, signed in; real `workspaces.default` |
| **Launch** | `vibelaunch claude --force` |
| **Result** | RECIPE OK (notes + inventory; no dedicated live card this cycle) |
| **Limitation** | — |
| **Status** | RECIPE OK — not scored broken |
| **Demo cue** | Open with Windows-native agent simplicity |

### 2. `claude-resume` — Claude Code (resume)

| | |
|--|--|
| **Purpose** | Continue last session with auto-approved tools |
| **Topology** | native_windows_scope |
| **Setup** | Prior session exists |
| **Launch** | `vibelaunch claude-resume --force` |
| **Result** | RECIPE OK; dry-run proves args `-c --dangerously-skip-permissions` |
| **Limitation** | Skip-permissions is intentional defaults — say so |
| **Status** | RECIPE OK |
| **Demo cue** | “Resume flag pair is explicit in notes after help audit.” |

### 3. `codex` — Codex (config cwd)

| | |
|--|--|
| **Purpose** | Interactive Windows Codex at config `cwd` |
| **Topology** | native_windows_scope |
| **Setup** | Windows `codex` + auth; understand cwd comes from defaults, not workspace map |
| **Launch** | `vibelaunch codex --force` |
| **Result** | RECIPE OK |
| **Limitation** | Quota/credits environmental |
| **Status** | RECIPE OK / HOST PREREQ if logged out |
| **Demo cue** | Contrast cwd vs `codex-workspace` |

### 4. `codex-workspace` — Codex → example workspace

| | |
|--|--|
| **Purpose** | Codex rooted on `workspaces.default` |
| **Topology** | native_windows_scope |
| **Setup** | Demo path exists; Windows codex auth |
| **Launch** | `vibelaunch codex-workspace --force` |
| **Result** | RECIPE OK |
| **Status** | RECIPE OK |
| **Demo cue** | Preferred Windows Codex filming preset |

### 5. `cmd-scroll-test` — cmd.exe scrollback

| | |
|--|--|
| **Purpose** | Prove keypad/PC scroll depth (not an agent) |
| **Topology** | native_windows_scope |
| **Setup** | None |
| **Launch** | `vibelaunch cmd-scroll-test --force` |
| **Result** | RECIPE OK / DIAG |
| **Status** | DIAG |
| **Demo cue** | Loop echo 100 lines; scroll; mention `--cols/--rows` or GUI PTY size |

### 6. `hermes-vk` — Hermes (VibeKeys) auto

| | |
|--|--|
| **Purpose** | Hermes chat + `vibekeys-hermes`, `HERMES_VIBEKEYS_SESSION=1` |
| **Topology** | conditional (WSL preferred when enabled) |
| **Setup** | WSL hermes **or** Windows hermes |
| **Launch** | `vibelaunch hermes-vk --force` (or token `hermes`) |
| **Result** | RECIPE OK |
| **Limitation** | Windows fallback is EXPECTED LIMIT if only WSL is provisioned |
| **Status** | RECIPE OK on WSL branch |
| **Demo cue** | “Auto topology — force with hermes wsl / windows.” |

### 7. `hermes-vk-wsl` — Hermes (VibeKeys, WSL)

| | |
|--|--|
| **Purpose** | Force WSL Hermes regardless of Windows PATH |
| **Topology** | expected_compatible (Win vibetty → wsl.exe → hermes) |
| **Setup** | `wsl.user=itgadmin`, hermes in WSL |
| **Launch** | `vibelaunch hermes-vk-wsl --force` |
| **Result** | RECIPE OK (live agent session not re-carded this cycle) |
| **Status** | RECIPE OK |
| **Demo cue** | Primary Hermes + keypad narrative |

### 8. `hermes-vk-win` — Hermes (VibeKeys, Windows)

| | |
|--|--|
| **Purpose** | Force native Windows Hermes (no WSL) |
| **Topology** | **expected_limitation** under WSL-service topology |
| **Setup** | Windows `hermes` on PATH + separate Windows auth |
| **Launch** | `vibelaunch hermes-vk-win --force` |
| **Result** | Do not treat missing Windows Hermes as preset bug |
| **Status** | **EXPECTED LIMIT** |
| **Demo cue** | Optional 10s: “Unsupported on this host by design.” |

### 9. `hermes-codex-workspace` — Hermes + Codex model (WSL)

| | |
|--|--|
| **Purpose** | WSL Hermes with spawn model pin `openai-codex/gpt-5.4` |
| **Topology** | expected_compatible |
| **Setup** | WSL hermes + Codex provider auth |
| **Launch** | `vibelaunch hermes-codex-workspace --force` |
| **Result** | RECIPE OK; Hermes Codex credits later OK on host |
| **Status** | RECIPE OK / HOST PREREQ without provider auth |
| **Demo cue** | Point at `-m` in recipe; `/model` inside chat |

### 10. `hermes-codex-workspace-win` — Hermes + Codex model (Windows)

| | |
|--|--|
| **Purpose** | Same pin on Windows Hermes |
| **Topology** | **expected_limitation** |
| **Status** | **EXPECTED LIMIT** |
| **Demo cue** | Skip unless Windows Hermes is installed for contrast |

### 11. `openclaw-vk` — OpenClaw TUI (vibekeys session)

| | |
|--|--|
| **Purpose** | Keypad-friendly OpenClaw TUI session |
| **Topology** | WSL-only (no Windows OpenClaw companion) |
| **Setup** | gateway, openclaw, `wsl.user` |
| **Launch** | `vibelaunch openclaw-vk --force` |
| **Result** | RECIPE OK |
| **Status** | RECIPE OK / HOST PREREQ if gateway down |
| **Demo cue** | Default OpenClaw film preset |

### 12. `openclaw-tui` — OpenClaw TUI (main)

| | |
|--|--|
| **Purpose** | Main gateway session (no `--session`) |
| **Topology** | WSL-only |
| **Status** | RECIPE OK |
| **Demo cue** | “Main can spam heartbeat — prefer openclaw-vk.” |

### 13. `openclaw-cursor-workspace` — OpenClaw → Cursor ACP

| | |
|--|--|
| **Purpose** | ACP **harness** spawn of Cursor at launch |
| **Topology** | WSL OpenClaw + acpx |
| **Setup** | `acp.enabled`, acpx plugin, `cursor` in `allowedAgents`, Cursor agent, `workspaces.default-wsl` |
| **Launch** | `vibelaunch openclaw-cursor-workspace --force` |
| **Result** | **PASS** — dry-run + Vibetty launch + `/acp spawn cursor` persistent/oneshot IDs recorded |
| **Limitation** | Host must enable ACP (not shipped as turnkey cloud config) |
| **Status** | **PASS** |
| **Remediation** | `docs/OPENCLAW_ACP.md`; `/acp doctor` |
| **Demo cue** | “Harness spawn string is the preset.” |
| **Evidence** | `review-artifacts/t_65a3dcb4-openclaw-acp-validation.md`, `.validation-cursor-acp/REPORT.md` |

### 14. `openclaw-codex-workspace` — OpenClaw → Codex ACP

| | |
|--|--|
| **Purpose** | ACP harness id `codex` (not native `/codex`) |
| **Topology** | WSL OpenClaw + acpx |
| **Setup** | `codex` allowlisted; agent command `npx -y @zed-industries/codex-acp`; auth in acpx codex-home |
| **Launch** | `vibelaunch openclaw-codex-workspace --force` |
| **Result** | **PASS*** after enablement; earlier **policy deny** + auth gaps were host config |
| **Limitation** | Never classify allowlist deny as broken recipe |
| **Status** | **PASS*** |
| **Remediation** | OPENCLAW_ACP runbook; sync `auth.json` into `~/.openclaw/acpx/codex-home` |
| **Demo cue** | Optional before/after allowlist — or jump to green spawn |
| **Evidence** | `review-artifacts/t_65a3dcb4-codex-reproof-2026-07-26.md` |

### 15. `hermes-acp-cursor` — Hermes → Cursor ACP (drop-in)

| | |
|--|--|
| **Purpose** | Hermes ACP *client* shell into live Cursor (not OpenClaw) |
| **Topology** | WSL python client → agent ACP |
| **Setup** | `~/bin/hermes-acp-client.py`, Cursor Pro agent |
| **Launch** | `vibelaunch hermes-acp-cursor --force` |
| **Behavioral proof** | `send cursor "…ACP_CLIENT_DROPIN_OK"` → OK; multi-turn memory OK |
| **Status** | **PASS** |
| **Limitation** | Rich Cursor permission UX / ask_question / create_plan not in basic scope |
| **Demo cue** | Best single “coding drop-in” shot |
| **Evidence** | `review-artifacts/hermes-acp-preset-validation.md`, `.validation-cursor-acp/REPORT.md` |

### 16. `hermes-acp-claude` — Hermes → Claude Code ACP (drop-in)

| | |
|--|--|
| **Purpose** | Drop-in via `npx @agentclientprotocol/claude-agent-acp` |
| **Setup** | Node, Claude auth, client script |
| **Launch** | `vibelaunch hermes-acp-claude --force` |
| **Behavioral proof** | `CLAUDE_ACP_OK` |
| **Status** | **PASS** |
| **Evidence** | `review-artifacts/hermes-acp-preset-validation.md` |

### 17. `hermes-acp-codex` — Hermes → Codex ACP (drop-in)

| | |
|--|--|
| **Purpose** | Drop-in via `npx @zed-industries/codex-acp` |
| **Setup** | Node, WSL `codex login`, client script |
| **Launch** | `vibelaunch hermes-acp-codex --force` |
| **Result** | Vibetty launch PASS; send failed with `Authentication required` until login/credits; then **HERMES_ACP_CODEX_OK** |
| **Status** | **PASS*** (HOST PREREQ when logged out) |
| **Remediation** | `codex login` in WSL — not a preset JSON change |
| **Demo cue** | Honest prereq story or post-auth only |
| **Evidence** | `hermes-acp-preset-validation.md` + codex reproof |

---

## Scoreboard (filming honesty)

| Bucket | Presets |
|--------|---------|
| **PASS** (live) | `hermes-acp-cursor`, `hermes-acp-claude`, `openclaw-cursor-workspace` |
| **PASS*** (live after host enablement) | `hermes-acp-codex`, `openclaw-codex-workspace` |
| **RECIPE OK** (not full live agent re-proof) | `claude`, `claude-resume`, `codex`, `codex-workspace`, `cmd-scroll-test`, `hermes-vk`, `hermes-vk-wsl`, `hermes-codex-workspace`, `openclaw-vk`, `openclaw-tui` |
| **EXPECTED LIMIT** (intentional; not broken) | `hermes-vk-win`, `hermes-codex-workspace-win` |
| **Broken presets** | **None identified** on canonical set @ `5aabb5b` |

---

## Evidence index

| Artifact | Role |
|----------|------|
| `config/presets.json` @ `5aabb5b` | Canonical 17 recipes + notes |
| `/home/itgadmin/reviews/t_d1c7db42-vibelaunch/review-artifacts/vibelaunch-preset-baseline.md` | Topology + inventory (older rev `314a613`; names still match) |
| `review-artifacts/hermes-acp-preset-validation.md` | t_2449e672 Hermes ACP vibetty + send |
| `review-artifacts/t_65a3dcb4-openclaw-acp-validation.md` | OpenClaw ACP initial validation |
| `review-artifacts/t_65a3dcb4-codex-reproof-2026-07-26.md` | Codex allowlist + hermes/openclaw codex OK |
| `.validation-cursor-acp/REPORT.md` | t_938cf5d4 Cursor ACP / vibetty |
| `review-artifacts/t_16c852c3-preset-help-clarity.md` | Notes/help/dry-run clarity |
| `review-artifacts/t_598e895b-link-check-report.md` | Doc link repair |
| `docs/HERMES_ACP_CLIENT.md` | Hermes ACP runbook |
| `docs/OPENCLAW_ACP.md` | OpenClaw ACP enablement |
| Obsidian pack | `Documents/Obsidian Vaults/Agents/Quill-HM/VibeLaunch-Review-2026-07-26` |

---

## Ops notes (not preset defects)

1. **Workspace fallback** — unresolved placeholders once resolved to `C:\Program Files`; host fixed via user `defaults.local.json`. Source hardening may exist only in clone until PF reinstall.
2. **Program Files lag** — install tree may lack post-`5aabb5b` notes/docs until copy/reinstall.
3. **Keypad hardware** — most proofs used vibetty bind + agent/ACP behavior; physical keypad optional for film B-roll.
4. **Secrets** — do not film or commit raw `vibetty_*.log` (ASR config).

---

## Acceptance (this tracker)

| Criterion | Met |
|-----------|-----|
| Durable Markdown in project docs | Yes — this file |
| Linked from project docs | README Related docs |
| Every canonical preset represented | 17/17 |
| Results trace to test evidence | Evidence column + index |
| Intentional unsupported vs broken | EXPECTED LIMIT / HOST PREREQ / none broken |
| On-camera usable | Filming order + short matrix + cues |
