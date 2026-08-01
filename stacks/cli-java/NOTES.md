# Stack notes — cli-java

> **TL;DR** — plain `javac`/`java`, no build tool. Stdin comes from a committed
> `sample-input.txt` through a `cmd /c` redirect — never a PowerShell pipe (BOM poison).

## Gotchas proven in the field

- **The BOM trap (why `cmd /c "... < sample-input.txt"`):** PowerShell's `Get-Content |`
  pipe prepends a UTF-8 BOM to the first stdin line, which crashes apps whose first read is
  numeric (`NumberFormatException`). The `cmd /c` redirection passes file bytes through
  untouched. Never "simplify" the run recipe back to a pipe.
- **`sample-input.txt`:** if the app reads stdin (`Scanner`), create and COMMIT a
  `sample-input.txt` with plausible values matching the exact read order (counts included) —
  a drifted file dies with `NoSuchElementException`. If the app takes no input, drop the
  redirection from the `run` recipe.
- **`@@MAIN_CLASS@@`** = the class containing `main()` (default package assumed; adjust
  `-cp`/package prefix if the sources declare one).
- **gitignore:** add `out/` (compiled classes) plus any file the app writes at runtime
  (check `git status` after a run).
- **No server:** there is no `start`/`stop`; boot-verify = `just build` + `just run` both
  exit 0 with no stack trace.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
