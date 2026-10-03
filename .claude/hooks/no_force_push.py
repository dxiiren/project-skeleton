"""PreToolUse hook: refuse any `git push` that can rewrite a remote branch.

The deny rules in settings.json are globs, and a glob cannot say "a push with a force flag
anywhere": `git -c k=v push -f`, `git --no-pager push -f`, `-uvf` and a quoted `"+ref"` all
slipped past 40-odd patterns (verifier, 2026-10-03). This hook TOKENISES the command instead and
blocks when, after `git [global options] push`, it sees `--force`/`--force-with-lease`/
`--force-if-includes`, `--mirror`, `--delete`/`-d`, a short-flag cluster containing `f` or `d`, a
`:ref` deletion, a refspec starting with `+`, a `-c <remote>.push=+...` config refspec, or any
of these inside a quoted sub-command (`bash -c '...'`), or a `git config` that arms a later push
(`alias.x 'push -f'`, `remote.o.push +...`). Also: unambiguous prefixes of the long options
(`--m`, `--mirr`), `remote.<name>.mirror` set by `-c`, `--config-env`, `GIT_CONFIG_KEY_n` or `git config`,
`git remote add --mirror`, the word `mirror` anywhere in a git config/remote/push command,
any `GIT_CONFIG_*` override next to git, PowerShell backtick escapes, a PowerShell `@splat`, `git send-pack`, `xargs git push`, and a `$VAR`/`$(...)` argument (except the
current-branch substitutions). Wired for the Bash AND PowerShell tools, on EVERY command (no text pre-filter -
a `*push*` filter once hid `send-pack` and `git config` from it). Known limits: an alias ALREADY in the user's git config,
a push run from inside a script file, and a git binary renamed or reached through another
program cannot be seen in the command text. GitHub branch protection is the server-side backstop.
Cases: test_no_force_push.py beside this file (`python .claude/hooks/test_no_force_push.py`). Exit 2 = blocked (stderr goes to the model).
"""
import json
import os
import re
import shlex
import sys

GIT_OPTS_WITH_VALUE = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
SEPARATORS = {"&&", "||", ";", "|", "&", "(", ")", "\n"}
BAD_LONG = ("--force", "--force-with-lease", "--force-if-includes", "--mirror", "--delete", "--prune")


def tokens(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:
        return command.split()


def is_git(tok):
    base = os.path.basename(tok.replace("\\", "/")).lower()
    return base in ("git", "git.exe")


SAFE_SUBST = re.compile(r"^\$\((git (branch --show-current|rev-parse --abbrev-ref HEAD))\)$")


def why_forced(args):
    for a in args:
        if a in SEPARATORS:
            break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            # git accepts any unambiguous prefix: --mirr, --dele, --force-w
            if len(name) >= 3 and any(b.startswith(name) for b in BAD_LONG):
                return a
        if a.startswith("@") and len(a) > 1:
            return a + " (PowerShell splat - write the push out literally)"
        if ("$" in a or "`" in a) and not SAFE_SUBST.match(a):
            return a + " (expands at run time - write the push out literally)"
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            cluster = a[1:]
            if "f" in cluster or "d" in cluster:
                return a
        if a.startswith("+") and len(a) > 1:
            return a
        if a.startswith(":") and len(a) > 1:
            return a + " (deletes a remote ref)"
    return None


def forcing_key(key, val):
    key = key.lower()
    if key.startswith("alias.") and "push" in val:
        return "alias"
    if key.endswith(".push") and val.lstrip().startswith("+"):
        return "forced refspec"
    if key.startswith("remote.") and key.endswith(".mirror"):
        return "mirror"
    return None


def forcing_config(args):
    """`git config [any options] alias.x 'push -f'` / `remote.o.push +...` arms a LATER plain command."""
    words = []
    for a in args:
        if a in SEPARATORS:
            break
        words.append(a)
    for n, w in enumerate(words):
        rest = " ".join(words[n + 1:])
        if forcing_key(w.split("=", 1)[0], rest if "=" not in w else w.split("=", 1)[1] + " " + rest):
            return "git config " + w
    return None


GIT_CONFIG_NAME = re.compile(r"^(?:\$env:)?GIT_CONFIG_(?:KEY_\d+|VALUE_\d+|COUNT|PARAMETERS)\b", re.I)
GIT_CONFIG_ENV = re.compile(r"GIT_CONFIG_(?:KEY_\d+|PARAMETERS)\s*=\s*['\"]?([^\s'\"]+)", re.I)


def check(command, depth=0):
    command = command.replace("`", "")  # PowerShell escape: pu`sh runs as push (a bash backtick flag stays visible)
    if re.search(r"GIT_CONFIG_(?:KEY_\d+|COUNT|PARAMETERS)", command, re.I) and re.search(r"\bgit\b", command, re.I):
        return "GIT_CONFIG_* override (config from the environment)"
    for m in GIT_CONFIG_ENV.finditer(command):
        if forcing_key(m.group(1).split("=", 1)[0], "push +"):
            return "GIT_CONFIG_* " + m.group(1) + " (config from the environment)"
    t = tokens(command)
    i = 0
    while i < len(t):
        tok = t[i]
        # a quoted sub-command (`bash -c 'git push -f'`, `sh -c "..."`) is scanned as a command too
        if depth < 3 and any(c.isspace() for c in tok) and "push" in tok:
            bad = check(tok, depth + 1)
            if bad:
                return bad
        if is_git(tok):
            end = next((n for n in range(i + 1, len(t)) if t[n] in SEPARATORS), len(t))
            start = max([n for n in range(i) if t[n] in SEPARATORS] + [-1]) + 1
            seg = [x.lower() for x in t[i + 1:end]]
            if any(GIT_CONFIG_NAME.match(x) for x in t[start:i]):
                return "GIT_CONFIG_* override in front of git (config from the environment)"
            sub = next((x for n, x in enumerate(seg) if not x.startswith("-")
                        and not (n > 0 and seg[n - 1] in GIT_OPTS_WITH_VALUE)), "")
            risky_globals = any(x.startswith(("-c", "--config-env")) for x in seg[:seg.index(sub)] if sub) if sub else False
            if (sub in ("config", "remote", "push", "send-pack") or risky_globals) and any("mirror" in x for x in seg):
                return "mirror (any spelling of a mirror remote or push)"
            j = i + 1
            while j < len(t) and t[j].startswith("-") and t[j] not in SEPARATORS:
                if t[j].startswith("--config-env"):
                    spec = t[j].split("=", 1)[1] if "=" in t[j] else (t[j + 1] if j + 1 < len(t) else "")
                    key = spec.split("=", 1)[0]
                    if forcing_key(key, "push +"):
                        return t[j] + " (config from the environment)"
                if t[j] == "-c" and j + 1 < len(t):
                    key, _, val = t[j + 1].partition("=")
                    # a forced refspec or force flag smuggled in through config
                    if key.lower().endswith(".push") and val.lstrip().startswith("+"):
                        return "-c " + t[j + 1]
                    if key.lower().startswith("remote.") and key.lower().endswith(".mirror"):
                        return "-c " + t[j + 1] + " (mirror push)"
                    if key.lower().startswith("alias.") and "push" in val:
                        return "-c " + t[j + 1] + " (push alias)"
                j += 2 if t[j] in GIT_OPTS_WITH_VALUE else 1
            if j < len(t) and t[j] in ("push", "send-pack"):
                bad = why_forced(t[j + 1:])
                if bad:
                    return bad
                # `... | xargs git push` takes its flags from stdin - never visible here
                seg = t[:i]
                k = max([n for n, x in enumerate(seg) if x in SEPARATORS - {"|"}] + [-1])
                if "xargs" in seg[k + 1:]:
                    return "xargs git " + t[j] + " (flags arrive on stdin)"
            if j < len(t) and t[j] == "config":
                bad = forcing_config(t[j + 1:])
                if bad:
                    return bad
            if j < len(t) and t[j] == "remote":
                for a in t[j + 1:]:
                    if a in SEPARATORS:
                        break
                    if a.startswith("--mirror"):
                        return "git remote " + a + " (mirror remote)"
        i += 1
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""
    bad = check(command)
    if bad:
        print(f"FORCE-PUSH GUARD: blocked `git push` with {bad!r} - pushes here never rewrite or delete a "
              "remote branch. Push normally, or ask the developer to run it themselves.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
