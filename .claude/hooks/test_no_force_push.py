"""Cases for no_force_push.py - run: python .claude/hooks/test_no_force_push.py (exit 1 on any miss)."""
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("nfp", os.path.join(os.path.dirname(os.path.abspath(__file__)), "no_force_push.py"))
nfp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nfp)

BLOCK = [
    "git push --force origin main", "git push -f", "git push origin main -f", "git push origin main --force",
    "git push --force-with-lease", "git push --force-with-lease=main:abc", "git push --force-if-includes --force-with-lease",
    "git push -nf x", "git push -fn x", "git push -vf x", "git push -qf x", "git push -uf x", "git push -fu x",
    "git push -uvf x", "git push -unf x", "git push -vqf x", "git push -qnf x",
    "git push origin +main", 'git push origin "+main"', "git push origin '+main:main'", "git push origin +HEAD:refs/heads/main",
    "git push --mirror origin", "git push --delete origin b", "git push -d origin b", "git push origin :b", "git push --prune origin",
    "git -C . push -f x", "git -C some/dir push --force x", "git -c a=b push -f x", "git --no-pager push -f x",
    "git --git-dir .git push -f", "git --work-tree=. push -f x", "/usr/bin/git push -f", "git.exe push --force=yes",
    "cd x && git push --force", "echo a; git push -fu origin x", "true || git push -f", "(git push -f)",
    "env git push -f", "command git push -f", "xargs git push -f", "nohup git push --force",
    "bash -c 'git push -f origin x'", 'sh -c "git push --force"', "eval 'git push -f'",
    "git -c remote.origin.push=+refs/heads/*:refs/heads/* push origin", "git -c alias.p='push -f' p",
    "git config alias.fp 'push -f'", "git config --global alias.fp 'push --force'",
    "git config remote.origin.push +refs/heads/main:refs/heads/main",
    "git push --mirr origin", "git push --dele origin y", "git push --force-w origin x", "git push --forc x",
    "F=--force; git push origin HEAD:x $F", "git push origin x $(echo --force)", "git push origin x `echo -f`",
    "echo -f | xargs git push origin HEAD:x", "git send-pack --force ../bare.git HEAD:refs/heads/x",
    "git send-pack ../bare.git +HEAD:refs/heads/x", "git config alias.zz \"push --force\"",
    "git config set alias.zz \"push -f\"",
    "git push --m origin", "git push --mi origin", "git -c remote.origin.mirror=true push origin",
    "git config remote.origin.mirror true && git push origin", "git push @a origin main",
    "$a=@('-f'); git push @a origin main",
]
ALLOW = [
    "git push", "git push -u origin feat/x", "git push --follow-tags", "git push -v origin main", "git -C . push origin main",
    "git status && git push -u origin HEAD", "git commit -m 'force push fix' && git push", "git push --dry-run origin main",
    "git push -q", "git push --set-upstream origin x", "git push --tags", "git -c color.ui=never push origin main",
    "bash -c 'git push origin x'", "git config alias.st status", "git config remote.origin.push refs/heads/main",
    "git fetch --force", "git pull -f", "gh pr merge --merge", "git log --format=%H -n1 && git push origin main",
    "git push -u origin \"$(git branch --show-current)\"", "git push -u origin \"$(git rev-parse --abbrev-ref HEAD)\"",
    "git push --porcelain origin main", "git push --no-verify origin x", "git push --tags origin",
    "ls | xargs echo && git push origin main",
]
miss = [c for c in BLOCK if not nfp.check(c)] + [c for c in ALLOW if nfp.check(c)]
for c in miss:
    print("MISCLASSIFIED:", c)
print(f"{len(BLOCK)} block + {len(ALLOW)} allow cases, {len(miss)} misclassified")
sys.exit(1 if miss else 0)
