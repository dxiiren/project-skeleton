#!/usr/bin/env python3
"""
PostToolUse hook (Edit|Write): a code file just changed and is UNPROVEN until
exercised against the actually-running system.

Judges the file that was ACTUALLY edited, taken from the hook payload on stdin.

It deliberately does NOT consult `git diff`. An adversarial verification of an
earlier git-based version proved three defects that all came from asking git
"what is dirty?" instead of "what was just edited?":
  - `git diff --name-only` never lists UNTRACKED files, so `Write` of a brand-new
    source file produced no reminder at all -- the case that matters most.
  - Once a change was `git add`-ed it left the unstaged diff, so staged code
    changes went silent too.
  - It fired on an edit to ANY file (README.md included) whenever ANY code file
    was dirty anywhere in the repo, because repo-wide dirt is not the edited file.
Reading tool_input.file_path removes all three by construction, and removes the
dependency on the hook's working directory at the same time.

Fires once per session so a long editing run does not repeat itself; delete the
marker logic if you want it on every edit.

[GROUND: trim CODE_EXT to the extensions this project actually ships, and point
the message at this project's real proof command -- its dev server URL, its e2e
runner, or its build-run pair.]
"""
import hashlib
import json
import os
import sys
import tempfile

# Extensions whose behaviour cannot be trusted from a build alone.
CODE_EXT = (
    ".java", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".svelte", ".vue",
    ".py", ".php", ".rb", ".go", ".rs", ".c", ".h", ".cpp", ".cs", ".vb",
    ".sql",
)

MESSAGE = (
    "Reminder: {name} is UNPROVEN until exercised against the actually-running "
    "system -- a real HTTP call, a real browser run, or the built artifact "
    "actually executed. A green build and mocked unit tests do not count."
)


def already_reminded(session_id):
    """True if this session was already reminded. Never raises."""
    if not session_id:
        return False
    try:
        key = hashlib.sha1(session_id.encode("utf-8")).hexdigest()[:16]
        marker = os.path.join(tempfile.gettempdir(), "cc-live-proof-" + key)
        if os.path.exists(marker):
            return True
        with open(marker, "w", encoding="utf-8") as fh:
            fh.write("1")
        return False
    except OSError:
        return False


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not path:
        sys.exit(0)

    if os.path.splitext(path)[1].lower() not in CODE_EXT:
        sys.exit(0)

    if already_reminded(payload.get("session_id")):
        sys.exit(0)

    print(MESSAGE.format(name=os.path.basename(path)))
    sys.exit(0)


if __name__ == "__main__":
    main()
