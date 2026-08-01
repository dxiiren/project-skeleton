# Stack notes — cli-jupyter

> **TL;DR** — notebooks run through uv (`uv run --with jupyter`), nothing installed
> globally. Extend the `--with` list to cover every library the committed notebooks import,
> or headless execution dies on the first missing import.

## Gotchas proven in the field

- **Extend `--with` to match the notebooks:** the `execute` recipe's dependency list must
  carry every library the committed notebooks import (e.g.
  `--with jupyter,nbclient,requests,pandas,matplotlib,seaborn,wordcloud`). Read the
  notebooks' import cells and extend the recipe accordingly.
- **Interactive / API-bound notebooks:** a notebook that calls `input()` or a live API may
  never exit 0 headlessly — document that in `.docs/06-troubleshooting/` instead of
  fighting it; pick a small self-contained notebook for boot-verify.
- **`lab` vs `serve`:** if the repo also contains a small web app (e.g. Flask), give it a
  `serve` recipe that shares the port with `lab` (run one at a time) and pass the app path
  ABSOLUTE so the repo path lands on the process command line — that's what lets
  `just stop` scope the kill.
- **gitignore:** add `.ipynb_checkpoints/` plus anything the notebooks write.
- **Boot-verify:** `just execute <small notebook>` (nbconvert `--execute`) exits 0.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
