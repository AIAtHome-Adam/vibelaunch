#!/usr/bin/env python3
"""hermes-acp-client — generalized ACP *client* for coding agents.

Hermes ships as an ACP *server* (`hermes acp`) but does not expose an ACP
*client* command. This adapter fills that gap: it lets Hermes drive any
ACP-compatible coding agent (Cursor, Claude Code, Codex, Gemini, ...) the
same way OpenClaw's `acpx` did — a live, typed, drop-in session over stdio
JSON-RPC instead of scraping a terminal.

The protocol implementation mirrors Hermes's own bundled
`agent/copilot_acp_client.py` (which drives `copilot --acp`), so it tracks
the real, working reference rather than a guess.

Upstream context: Hermes issue #5257 ("Generalized ACP client for
multi-agent CLI orchestration") proposes the same thing in core. This script
is a standalone, dependency-free stopgap until that lands — it converges with
#5257 and can be retired once `hermes --provider {agent}-acp` ships.

Agents (command resolved via env override HERMES_ACP_{NAME}_COMMAND):
  cursor  -> agent acp                  (Cursor Pro CLI; ACP server mode)
  claude  -> npx @agentclientprotocol/claude-agent-acp
  codex   -> npx @zed-industries/codex-acp
  gemini  -> gemini --acp
  (any other name falls through to `HERMES_ACP_{NAME}_COMMAND` or `{name} acp`)

Usage:
  hermes-acp-client.py send <agent> "prompt" [--cwd PATH] [--approve]
  hermes-acp-client.py shell <agent> [--cwd PATH] [--approve]
      (shell: persistent session; type prompts on stdin, Ctrl-D / 'exit' quits)

No external dependencies (Python stdlib only). Run with any python3.
Auth uses each agent's own subscription (Cursor Pro / Claude Pro / ChatGPT
Plus-Pro Codex) — no API keys required.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any

DEFAULT_TIMEOUT = 900.0

# Registry: default launch commands. Env override HERMES_ACP_{NAME}_COMMAND
# (and HERMES_ACP_{NAME}_ARGS) wins. Mirrors #5257's design intent.
DEFAULT_COMMANDS: dict[str, list[str]] = {
    "cursor": ["agent", "acp"],
    "claude": ["npx", "@agentclientprotocol/claude-agent-acp"],
    "codex": ["npx", "@zed-industries/codex-acp"],
    "gemini": ["gemini", "--acp"],
}


def _resolve_command(agent: str) -> tuple[list[str], str]:
    """Return (argv, label) for the agent's ACP server command."""
    env_cmd = os.getenv(f"HERMES_ACP_{agent.upper()}_COMMAND")
    if env_cmd:
        return shlex.split(env_cmd), env_cmd
    env_args = os.getenv(f"HERMES_ACP_{agent.upper()}_ARGS")
    if env_args:
        return DEFAULT_COMMANDS.get(agent, [agent, "acp"]) + shlex.split(env_args), agent
    if agent in DEFAULT_COMMANDS:
        return list(DEFAULT_COMMANDS[agent]), agent
    # Fallback: assume `<agent> acp` (e.g. kiro, kilocode, opencode, ...)
    return [agent, "acp"], agent


def _ensure_path_within_cwd(path_text: str, cwd: str) -> Path:
    candidate = Path(path_text)
    if not candidate.is_absolute():
        raise PermissionError("ACP file-system paths must be absolute.")
    resolved = candidate.resolve()
    root = Path(cwd).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise PermissionError(
            f"Path '{resolved}' is outside the session cwd '{root}'."
        ) from exc
    return resolved


def _subprocess_env() -> dict[str, str]:
    """Child env. Inherit most; strip obvious Hermes/gateway secrets is the
    job of a hardened deploy, but for local single-user use we inherit PATH +
    HOME + agent creds. Cursor/Claude/Codex read their own auth from disk."""
    env = dict(os.environ)
    return env


class ACPClient:
    """Minimal async-free ACP client over a subprocess stdio JSON-RPC pipe."""

    def __init__(self, agent: str, cwd: str, approve: bool = False,
                 timeout: float = DEFAULT_TIMEOUT):
        self.agent = agent
        self.cwd = str(Path(cwd or os.getcwd()).resolve())
        self.approve = approve
        self.timeout = timeout
        self.argv, self.label = _resolve_command(agent)
        self.proc: subprocess.Popen[str] | None = None
        self.inbox: queue.Queue[dict[str, Any]] = queue.Queue()
        self._stderr_tail: deque[str] = deque(maxlen=40)
        self._next_id = 0
        self.session_id: str | None = None
        self._lock = threading.Lock()

    # -- lifecycle -------------------------------------------------------
    def start(self) -> None:
        try:
            self.proc = subprocess.Popen(
                self.argv,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                cwd=self.cwd,
                env=_subprocess_env(),
            )
        except FileNotFoundError as exc:
            raise RuntimeError(
                f"Could not start ACP command {self.argv!r}. Install the agent "
                f"or set HERMES_ACP_{self.agent.upper()}_COMMAND."
            ) from exc

        if self.proc.stdout is None or self.proc.stdin is None:
            self.proc.kill()
            raise RuntimeError("ACP process did not expose stdio pipes.")

        t_out = threading.Thread(target=self._stdout_reader, daemon=True)
        t_err = threading.Thread(target=self._stderr_reader, daemon=True)
        t_out.start()
        t_err.start()

        # Handshake
        self._request("initialize", {
            "protocolVersion": 1,
            "clientCapabilities": {
                "fs": {"readTextFile": True, "writeTextFile": True}
            },
            "clientInfo": {
                "name": "hermes-acp-client",
                "title": "Hermes ACP Client",
                "version": "0.1.0",
            },
        })
        session = self._request("session/new", {
            "cwd": self.cwd,
            "mcpServers": [],
        }) or {}
        sid = str(session.get("sessionId") or "").strip()
        if not sid:
            raise RuntimeError("ACP server did not return a sessionId.")
        self.session_id = sid

    def close(self) -> None:
        if self.proc is None:
            return
        if self.session_id:
            try:
                self._request("session/close", {"sessionId": self.session_id},
                              raise_on_error=False)
            except Exception:
                pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=2)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass
        self.proc = None

    # -- prompt ----------------------------------------------------------
    def prompt(self, text: str, *,
               stream: bool = False) -> str:
        """Send one prompt on the live session; return collected assistant text."""
        text_parts: list[str] = []
        reasoning_parts: list[str] = []
        self._request(
            "session/prompt",
            {
                "sessionId": self.session_id,
                "prompt": [{"type": "text", "text": text}],
            },
            text_parts=text_parts,
            reasoning_parts=reasoning_parts,
            stream=stream,
        )
        return "".join(text_parts)

    # -- internals -------------------------------------------------------
    def _stdout_reader(self) -> None:
        assert self.proc is not None and self.proc.stdout is not None
        for line in self.proc.stdout:
            try:
                self.inbox.put(json.loads(line))
            except Exception:
                self.inbox.put({"raw": line.rstrip("\n")})

    def _stderr_reader(self) -> None:
        assert self.proc is not None and self.proc.stderr is not None
        for line in self.proc.stderr:
            self._stderr_tail.append(line.rstrip("\n"))

    def _request(self, method: str, params: dict[str, Any], *,
                 text_parts: list[str] | None = None,
                 reasoning_parts: list[str] | None = None,
                 stream: bool = False,
                 raise_on_error: bool = True) -> Any:
        assert self.proc is not None and self.proc.stdin is not None
        self._next_id += 1
        rid = self._next_id
        payload = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()

        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                break
            try:
                msg = self.inbox.get(timeout=0.1)
            except queue.Empty:
                continue
            if self._handle_server_message(
                msg, text_parts=text_parts, reasoning_parts=reasoning_parts,
                stream=stream,
            ):
                continue
            if msg.get("id") != rid:
                continue
            if "error" in msg and raise_on_error:
                err = msg.get("error") or {}
                raise RuntimeError(f"ACP {method} failed: {err.get('message') or err}")
            return msg.get("result")
        stderr_text = "\n".join(self._stderr_tail).strip()
        if self.proc.poll() is not None and stderr_text:
            raise RuntimeError(f"ACP process exited early: {stderr_text}")
        raise TimeoutError(f"Timed out waiting for ACP response to {method}.")

    def _handle_server_message(self, msg: dict[str, Any], *,
                               text_parts: list[str] | None,
                               reasoning_parts: list[str] | None,
                               stream: bool) -> bool:
        method = msg.get("method")
        if not isinstance(method, str):
            return False
        if method == "session/update":
            params = msg.get("params") or {}
            update = params.get("update") or {}
            kind = str(update.get("sessionUpdate") or "").strip()
            content = update.get("content") or {}
            chunk = ""
            if isinstance(content, dict):
                chunk = str(content.get("text") or "")
            if kind == "agent_message_chunk" and chunk and text_parts is not None:
                text_parts.append(chunk)
                if stream:
                    sys.stdout.write(chunk)
                    sys.stdout.flush()
            elif kind == "agent_thought_chunk" and chunk and reasoning_parts is not None:
                reasoning_parts.append(chunk)
            return True
        if self.proc is None or self.proc.stdin is None:
            return True
        mid = msg.get("id")
        params = msg.get("params") or {}
        if method == "session/request_permission":
            response = {
                "jsonrpc": "2.0", "id": mid,
                "result": {"outcome": "approved" if self.approve else "cancelled"}
                if self.approve else
                {"outcome": "cancelled"},
            }
        elif method == "fs/read_text_file":
            try:
                path = _ensure_path_within_cwd(str(params.get("path") or ""), self.cwd)
                content = path.read_text() if path.exists() else ""
                line = params.get("line")
                limit = params.get("limit")
                if isinstance(line, int) and line > 1:
                    lines = content.splitlines(keepends=True)
                    start = line - 1
                    end = start + limit if isinstance(limit, int) and limit > 0 else None
                    content = "".join(lines[start:end])
                response = {"jsonrpc": "2.0", "id": mid, "result": {"content": content}}
            except Exception as exc:
                response = {"jsonrpc": "2.0", "id": mid,
                            "error": {"code": -32602, "message": str(exc)}}
        elif method == "fs/write_text_file":
            try:
                path = _ensure_path_within_cwd(str(params.get("path") or ""), self.cwd)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(str(params.get("content") or ""))
                response = {"jsonrpc": "2.0", "id": mid, "result": None}
            except Exception as exc:
                response = {"jsonrpc": "2.0", "id": mid,
                            "error": {"code": -32602, "message": str(exc)}}
        else:
            response = {"jsonrpc": "2.0", "id": mid,
                        "error": {"code": -32601,
                                  "message": f"ACP method '{method}' not supported."}}
        self.proc.stdin.write(json.dumps(response) + "\n")
        self.proc.stdin.flush()
        return True


def main() -> int:
    ap = argparse.ArgumentParser(description="Hermes ACP client for coding agents")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("send", help="one-shot prompt")
    sp.add_argument("agent")
    sp.add_argument("prompt")
    sp.add_argument("--cwd", default=os.getcwd())
    sp.add_argument("--approve", action="store_true",
                    help="auto-approve permission requests (recommended)")

    sh = sub.add_parser("shell", help="persistent drop-in session")
    sh.add_argument("agent")
    sh.add_argument("--cwd", default=os.getcwd())
    sh.add_argument("--approve", action="store_true",
                    help="auto-approve permission requests (recommended)")

    args = ap.parse_args()

    client = ACPClient(args.agent, args.cwd, approve=getattr(args, "approve", False))
    try:
        client.start()
        if args.cmd == "send":
            out = client.prompt(args.prompt, stream=True)
            if not out.endswith("\n"):
                sys.stdout.write("\n")
            return 0
        else:
            print(f"[hermes-acp] connected to {client.label} "
                  f"(session {client.session_id[:8] if client.session_id else '?'})")
            print("[hermes-acp] persistent session — type prompts; 'exit' or Ctrl-D quits.")
            while True:
                try:
                    line = input("› ")
                except (EOFError, KeyboardInterrupt):
                    print()
                    break
                if line.strip().lower() in {"exit", "quit"}:
                    break
                if not line.strip():
                    continue
                try:
                    client.prompt(line, stream=True)
                    sys.stdout.write("\n")
                except Exception as e:
                    print(f"[hermes-acp] error: {e}", file=sys.stderr)
            return 0
    except Exception as e:
        print(f"[hermes-acp] {e}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
