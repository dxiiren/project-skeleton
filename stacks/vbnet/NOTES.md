# Stack notes — vbnet (WinForms, .NET Framework 4.x)

> **TL;DR** — old-style `.vbproj` solutions build with MSBuild resolved down a two-path
> ladder: VS Build Tools 2022 if present, else the Framework MSBuild that ships with
> Windows. NEVER auto-install Build Tools from setup.ps1 — its installer needs UAC
> elevation and hangs unattended runs.

## Token mapping for this stack

| Token | Meaning here |
| --- | --- |
| `@@SRC@@` | The solution file name, including `.sln` (e.g. `My App.sln`) |
| `@@MAIN_CLASS@@` | The WinForms project name = project folder AND exe base name (e.g. `My App` for `My App\bin\Debug\My App.exe`) |

## Gotchas proven in the field

- **MSBuild resolution (two paths, in order):**
  1. VS Build Tools 2022: `%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe` — builds warning-free.
  2. Framework MSBuild: `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe` — ships
     with Windows, builds old-style `.vbproj` fine and produces a working exe.
  Both setup.ps1 (detection only) and the justfile `msbuild` variable resolve this way.
- **NEVER auto-install VS Build Tools** in setup.ps1: the installer requires UAC elevation
  and HANGS unattended runs (verified: winget exit 1602). Print a DarkGray note that a
  manual, elevated install removes the warnings instead.
- **Three benign warnings under Framework MSBuild** — expected, exit code 0 is a PASS:
  ToolsVersion 15.0 -> 4.0 fallback, MSB3644 (missing targeting pack -> GAC fallback), and
  MSB3270 (MSIL/AMD64 architecture note). Document them in `.docs/06-troubleshooting/`;
  don't "fix" them.
- **Delete stale `obj/`/`bin/` caches** copied from any archive BEFORE the first build — a
  stale `GenerateResource.Cache` causes MSB3088 warnings.
- **GUI boot-verify (no HTTP probe):** `just build` exits 0, `just run` launches the exe,
  confirm the process is still alive after ~5 s (`Get-Process` by path), then `just stop`.
- **Flat-file runtime data** (e.g. a credentials text file the app writes next to the exe):
  git-ignore the filename and document that the app creates it on first use.
- **`*.Designer.vb` files** are designer-generated — hand-edits are legitimate in this
  workflow but keep them minimal and consistent with the generated style.
- **gitignore:** `bin/`, `obj/`, `.vs/`, `*.user`, plus the shared claude block.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
