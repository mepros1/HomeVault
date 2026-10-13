"""Check tracked paths and common credential signatures without printing values.

This is a focused publication check, not a complete secret/history audit.
Run after staging the source.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "-z"], text=True
).split("\0")
signatures = [
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    re.compile(r"gh[pousr]_[0-9A-Za-z]{30,}"),
    re.compile(r"github_pat_[0-9A-Za-z_]{40,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?m)^-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\s*$"),
]
blocked = []
files = [p for p in paths if p]
if not files:
    print("No tracked files. Stage the publication source before running this check.")
    sys.exit(1)
for name in files:
    path = Path(name)
    forbidden = (
        (path.name.startswith(".env") and path.name != ".env.example")
        or path.name in {"key.properties", "local.properties"}
        or path.suffix.lower() in {".jks", ".keystore", ".pem", ".p12", ".pfx"}
        or any(part in {".dart_tool", ".gradle", "build", "target"} for part in path.parts)
        or re.search(r"service[-_]account.*\.json$", path.name, re.I)
    )
    if forbidden:
        blocked.append((name, "local artifact or credential path"))
        continue
    content = (root / path).read_bytes().decode("utf-8", errors="ignore")
    if any(pattern.search(content) for pattern in signatures):
        blocked.append((name, "possible credential signature"))
for name, reason in blocked:
    print(f"BLOCKED: {name} ({reason})")
print(f"Checked {len(files)} tracked files; findings: {len(blocked)}.")
sys.exit(1 if blocked else 0)
