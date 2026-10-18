#!/usr/bin/env python3
"""Check tracked text for unreviewed Chinese content without reading private data.

Install tools/requirements-language.txt, then run this file from any directory.
The policy records reviewed CJK text fingerprints, not blanket directory exemptions.
Comments and docstrings must be English even in localized application files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from pygments.lexers import get_lexer_for_filename
from pygments.lexers.html import XmlLexer
from pygments.lexers.shell import BashLexer
from pygments.token import Comment, String
from pygments.util import ClassNotFound

CJK = re.compile(r"[\u2e80-\u303f\u3400-\u9fff\uf900-\ufaff\uff01-\uff60\uffe0-\uffee\U00020000-\U0002fa1f]")
MEDIA = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".m4a", ".wav", ".mp3", ".mp4", ".mov", ".pdf", ".zip"}
CODE = {".swift", ".py", ".sh", ".command", ".js", ".cjs", ".mjs", ".ts", ".tsx", ".sql", ".html", ".css", ".plist", ".xcscheme", ".entitlements", ".pbxproj"}
ARCHIVES = {"docs/audit/member_a_audit_2026-10-08.json", "video/footage/record.log"}


def exclusion(path):
    """Return a documented exclusion before opening any file."""
    p = Path(path)
    if path.startswith("server/private/") and path != "server/private/README.md":
        return "private provider configuration"
    if p.name.startswith((".env", "Secrets.", "Local.xcconfig")) or p.suffix in {".key", ".pem", ".p12", ".db", ".sqlite3"}:
        return "private configuration or credential-related file"
    if p.suffix in MEDIA:
        return "original media"
    if path in ARCHIVES or path.startswith("wip/") and p.suffix == ".patch":
        return "original audit, patch, or recording evidence"
    return None


def fingerprint(text):
    chars = CJK.findall(text)
    return {"characters": len(chars), "sha256": hashlib.sha256("".join(chars).encode("utf-8")).hexdigest()}


def comment_issues(path, text):
    suffix = Path(path).suffix
    if suffix not in CODE:
        return []
    try:
        if suffix in {".plist", ".xcscheme", ".entitlements"}:
            lexer = XmlLexer()
        elif suffix == ".command":
            lexer = BashLexer()
        else:
            lexer = get_lexer_for_filename(path)
        tokens = lexer.get_tokens_unprocessed(text)
    except ClassNotFound:
        if suffix == ".pbxproj":
            return [f"{path}:{text[:m.start()].count(chr(10)) + 1}: CJK in comment" for m in re.finditer(r"/\*.*?\*/|//[^\n]*", text, re.S) if CJK.search(m[0])]
        return [f"{path}: no lexer available for comment verification"]
    return [f"{path}:{text[:start].count(chr(10)) + 1}: CJK in comment/docstring"
            for start, token, value in tokens
            if (token in Comment or suffix == ".py" and token in String.Doc) and CJK.search(value)]


def audit(root, policy):
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode("utf-8").split("\0")
    allowed = policy["text_exceptions"]
    names = set(policy["legacy_paths"])
    issues, skipped, used = [], {}, set()
    checked = 0
    for rel in filter(None, paths):
        reason = exclusion(rel)
        if reason:
            skipped[reason] = skipped.get(reason, 0) + 1
            continue
        if CJK.search(rel) and rel not in names:
            issues.append(f"{rel}: unreviewed CJK filename")
        path = root / rel
        if not path.is_file():
            issues.append(f"{rel}: tracked text unavailable; expand the sparse checkout")
            continue
        try:
            text = path.read_bytes().decode("utf-8-sig")
        except UnicodeDecodeError:
            issues.append(f"{rel}: unclassified binary or non-UTF-8 file")
            continue
        checked += 1
        issues.extend(comment_issues(rel, text))
        if CJK.search(text):
            entry = allowed.get(rel)
            if not entry or not entry.get("reason") or fingerprint(text) != entry.get("fingerprint"):
                issues.append(f"{rel}: CJK text differs from its reviewed exception; review the actual change")
            else:
                used.add(rel)
        elif rel in allowed:
            issues.append(f"{rel}: stale exception; remove it after reviewing the change")
    for rel in allowed.keys() - set(paths):
        issues.append(f"{rel}: exception refers to an untracked file")
    return {"checked_text_files": checked, "reviewed_text_exceptions": len(used), "excluded_files": skipped, "issues": issues}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    policy = json.loads((args.root / "tools/language-exceptions.json").read_text(encoding="utf-8"))
    result = audit(args.root, policy)
    print(json.dumps(result, indent=2))
    return bool(result["issues"])


if __name__ == "__main__":
    sys.exit(main())
