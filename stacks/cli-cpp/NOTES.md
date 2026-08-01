# Stack notes — cli-cpp

> **TL;DR** — g++ from a portable w64devkit zip at a pinned path. The build recipe MUST
> prepend the w64devkit bin dir to PATH (g++ finds its assembler via PATH), and stdin uses
> the `cmd /c` redirect, never a PowerShell pipe.

## Gotchas proven in the field

- **Assembler PATH-prepend (do not remove):** g++ resolves its assembler `as` via PATH, so
  the `build` recipe prepends `(Split-Path '{{gpp}}')` to `$env:Path` even though g++
  itself is invoked by absolute path. Without it, compiles fail with
  `cannot find as` / `CreateProcess` errors on machines where w64devkit isn't on PATH.
- **The BOM trap:** PowerShell's `Get-Content |` pipe prepends a UTF-8 BOM to the first
  stdin line (crashes apps whose first read is numeric). Keep the
  `cmd /c "out\app.exe < sample-input.txt"` redirection. If the program takes no input,
  drop the redirection.
- **`@@SRC@@`** = the source file name(s) passed to g++ (space-separated if several).
- **sample-input.txt:** committed, matching the exact `cin` read order.
- **w64devkit install** resolves the latest release via `gh api` — needs `gh` authenticated;
  otherwise setup prints a manual-install warning (not a failure).
- **gitignore:** add `out/` plus anything the app writes at runtime.
- **No server:** boot-verify = `just build` + `just run` both exit 0 with no stack trace.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
