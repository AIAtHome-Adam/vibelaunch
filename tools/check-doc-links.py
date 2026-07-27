#!/usr/bin/env python3
"""Reproducible VibeLaunch documentation / help link checker.

Scans Markdown hyperlinks under the repo root (plus a tight set of config/code
path references), classifies each link, and exits non-zero when any internal
reference is missing.

Usage:
  python3 tools/check-doc-links.py
  python3 tools/check-doc-links.py --root /path/to/vibelaunch --json report.json --md report.md
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.parse
from collections import Counter
from pathlib import Path

MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
# Tight path-like .md references in config/code (no spaces, no message prose).
CODE_MD_RE = re.compile(
    r"""(?P<q>['"])(?P<path>(?:(?:\.\.?/|docs/|skills/|config/|gui/|tools/|lib/)[\w./\\-]+|[\w.-]+)\.md)(?P=q)"""
)

SKIP_DIR_NAMES = {".git", "bin", "obj", "node_modules", ".vs", "review-artifacts", ".validation-cursor-acp"}
SKIP_FILES = {"tools/check-doc-links.py"}
SKIP_NAME_SUFFIXES = (".link-check-report.json", "link-check-report.json", "link-check-report.md")


def git_head(root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return "unknown"


def is_external(url: str) -> bool:
    u = url.strip()
    return bool(re.match(r"^(https?|mailto|ftp):", u, re.I)) or u.startswith("//")


def strip_frag(url: str) -> tuple[str, str | None]:
    parts = url.split("#", 1)
    base = parts[0].split("?", 1)[0]
    frag = parts[1] if len(parts) > 1 else None
    return base, frag


def iter_files(root: Path):
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in SKIP_DIR_NAMES for part in p.parts):
            continue
        rel = p.relative_to(root).as_posix()
        if rel in SKIP_FILES:
            continue
        if any(rel.endswith(suf) or p.name.endswith(suf) for suf in SKIP_NAME_SUFFIXES):
            continue
        if p.name.startswith("t_") and "link-check" in p.name:
            continue
        if p.suffix.lower() in {
            ".md",
            ".json",
            ".ps1",
            ".psm1",
            ".cs",
            ".xaml",
            ".cmd",
            ".py",
            ".example",
            ".txt",
        }:
            yield p


def collect_links(root: Path) -> list[dict]:
    links: list[dict] = []
    for f in sorted(iter_files(root)):
        rel = f.relative_to(root).as_posix()
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        for m in MD_LINK_RE.finditer(text):
            url = m.group(2).strip()
            # Ignore regex / placeholder examples
            if url in {".*", ".+", "..."} or re.match(r"^\$", url):
                continue
            # Character-class noise from this file or similar
            if "[^" in url or url.startswith("(?") or "\\\\" in url and "md" in url and "[" in m.group(0):
                continue
            line = text.count("\n", 0, m.start()) + 1
            links.append(
                {
                    "source": rel,
                    "line": line,
                    "kind": "md-link",
                    "label": m.group(1),
                    "url": url,
                }
            )

        if f.suffix.lower() in {".cs", ".ps1", ".psm1", ".py", ".json", ".cmd", ".example"}:
            for m in CODE_MD_RE.finditer(text):
                url = m.group("path").replace("\\", "/")
                line = text.count("\n", 0, m.start()) + 1
                links.append(
                    {
                        "source": rel,
                        "line": line,
                        "kind": "code-md-string",
                        "label": "",
                        "url": url,
                    }
                )
    return links


def classify(root: Path, link: dict) -> dict:
    url = link["url"].strip().strip("\"'")
    src = root / link["source"]
    entry = dict(link)

    if not url or url.startswith("#"):
        entry.update(status="ok-fragment", target_kind="fragment", resolved=None)
        return entry
    if is_external(url):
        entry.update(status="ok-external", target_kind="external", resolved=url)
        return entry

    # Intentional deploy destinations (not repo paths).
    if url.startswith(("~/", ".hermes/", "%", "$HOME", "${", "~")):
        entry.update(
            status="ok-exception-deploy-target",
            target_kind="deploy-target",
            resolved=url,
            exception="Install destination path documented intentionally; not a repo file.",
        )
        return entry

    base, _frag = strip_frag(url)
    base = urllib.parse.unquote(base).replace("\\", "/")
    if not base:
        entry.update(status="ok-fragment", target_kind="fragment", resolved=None)
        return entry

    candidates: list[Path] = []
    if base.startswith("/") and not base.startswith("//"):
        candidates.append((root / base.lstrip("/")).resolve())
    else:
        candidates.append((src.parent / base).resolve())
        candidates.append((root / base).resolve())
        name = Path(base).name
        if "/" not in base:
            candidates.append((root / "docs" / name).resolve())

    resolved = None
    exists = False
    for c in candidates:
        try:
            if c.exists():
                exists = True
                try:
                    resolved = c.relative_to(root.resolve()).as_posix()
                except ValueError:
                    resolved = str(c)
                break
        except OSError:
            continue

    entry["resolved"] = resolved
    entry["target_kind"] = "internal"
    entry["status"] = "ok" if exists else "missing"
    return entry


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, default=Path.cwd())
    ap.add_argument("--json", type=Path, help="Write full JSON report here")
    ap.add_argument("--md", type=Path, help="Write Markdown summary here")
    args = ap.parse_args()
    root = args.root.resolve()

    classified = [classify(root, L) for L in collect_links(root)]
    counts = Counter(c["status"] for c in classified)
    missing = [c for c in classified if c["status"] == "missing"]
    exceptions = [c for c in classified if c["status"].startswith("ok-exception")]

    report = {
        "root": str(root),
        "commit": git_head(root),
        "summary": {
            "total": len(classified),
            "ok": counts.get("ok", 0) + counts.get("ok-fragment", 0),
            "external": counts.get("ok-external", 0),
            "exceptions": len(exceptions),
            "missing": len(missing),
            "by_status": dict(counts),
        },
        "exceptions": exceptions,
        "missing": missing,
        "all": classified,
        "notes": [
            "Source-tree Markdown links to docs/VIBEKEYS_REMOTE.md resolve.",
            "vibelaunch gui-links resolves runbookPath to docs/VIBEKEYS_REMOTE.md under install root.",
            "Observed Help→runbook failure: temp HTML left relative HERMES_ACP_CLIENT.md dead; fixed in HelpContentRenderer.",
        ],
    }

    print(f"root: {root}")
    print(f"commit: {report['commit']}")
    print(
        f"total={report['summary']['total']} ok={report['summary']['ok']} "
        f"external={report['summary']['external']} exceptions={report['summary']['exceptions']} "
        f"missing={report['summary']['missing']}"
    )
    if missing:
        print("MISSING:")
        for m in missing:
            print(f"  {m['source']}:{m['line']} [{m['kind']}] {m['url']!r}")
    if exceptions:
        print("EXCEPTIONS (intentional):")
        for e in exceptions:
            print(f"  {e['source']}:{e['line']} {e['url']!r} — {e.get('exception')}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"wrote {args.json}")

    if args.md:
        lines = [
            "# VibeLaunch documentation link check",
            "",
            f"- Root: `{root}`",
            f"- Commit: `{report['commit']}`",
            f"- Total references: **{report['summary']['total']}**",
            f"- Internal OK: **{report['summary']['ok']}**",
            f"- External: **{report['summary']['external']}**",
            f"- Documented exceptions: **{report['summary']['exceptions']}**",
            f"- Missing: **{report['summary']['missing']}**",
            "",
            "## Observed runbook failure (explained)",
            "",
            "Source tree links to `docs/VIBEKEYS_REMOTE.md` resolve. `vibelaunch gui-links` sets",
            "`runbookPath` to that file under the install/clone root. The user-visible failure was",
            "Help → Open runbook (in-app / browser): Markdown was converted to HTML under",
            "`%TEMP%\\VibeLaunch\\help\\` without rewriting relative links, so",
            "`[HERMES_ACP_CLIENT.md](HERMES_ACP_CLIENT.md)` pointed at a missing temp-neighbor file.",
            "Fixed in `HelpContentRenderer` by rendering linked local `.md` into the help dir and",
            "rewriting `href`s to those HTML files; `HelpWindow` navigates via `file://`.",
            "",
            "## Missing",
            "",
        ]
        if not missing:
            lines.append("_None._")
        else:
            lines += ["| Source | Line | Kind | URL |", "|--------|------|------|-----|"]
            for m in missing:
                lines.append(
                    f"| `{m['source']}` | {m['line']} | {m['kind']} | `{m['url']}` |"
                )
        lines += ["", "## Intentional exceptions", ""]
        if not exceptions:
            lines.append("_None._")
        else:
            lines += ["| Source | Line | URL | Reason |", "|--------|------|-----|--------|"]
            for e in exceptions:
                lines.append(
                    f"| `{e['source']}` | {e['line']} | `{e['url']}` | {e.get('exception', '')} |"
                )
        lines.append("")
        lines.append("## Reproduce")
        lines.append("")
        lines.append("```bash")
        lines.append("python3 tools/check-doc-links.py --json /tmp/vl-links.json --md /tmp/vl-links.md")
        lines.append("```")
        lines.append("")
        args.md.parent.mkdir(parents=True, exist_ok=True)
        args.md.write_text("\n".join(lines), encoding="utf-8")
        print(f"wrote {args.md}")

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
