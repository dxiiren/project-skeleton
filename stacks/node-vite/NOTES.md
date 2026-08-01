# Stack notes — node-vite

> **TL;DR** — Vite dev server on a pinned port with `--strictPort`. On Windows, Node 17+
> binds `[::1]` (IPv6) only — every URL in docs and probes MUST use `localhost`, never
> `127.0.0.1`.

## Gotchas proven in the field

- **`localhost`, not `127.0.0.1`:** Vite/Node >= 17 binds `[::1]` only on Windows; an IPv4
  probe gets connection-refused on a perfectly healthy server. Use
  `http://localhost:@@PORT@@` in README/CLAUDE/docs/curl checks, everywhere.
- **`--strictPort` stays:** without it Vite silently hops to the next free port and every
  documented URL is wrong. The kit justfile already passes it.
- **Test script naming:** Vue scaffolds name the script `test:unit`, not `test` — adapt the
  recipe (`npm run test:unit -- --run {{flags}}`) AND force run-once mode: bare vitest
  enters watch mode in a TTY and hangs the recipe. Same rule for any vitest script.
- **Recipe pruning:** keep only the recipes whose npm script exists in `package.json`
  (`lint`, `format`, `test`, `preview`); delete the rest. `preview` needs a prior `build`.
- **Dev script must be plain `vite`:** the justfile appends `-- --port {{port}} --strictPort`;
  if the package.json dev script already hardcodes flags, reconcile there.
- **E2E (Cypress etc.):** do NOT add an e2e recipe unless it runs headless reliably; note it
  in `.docs/` instead.
- **Boot-verify:** `just install` + `just build` exit 0, then `just start`, then GET
  `http://localhost:@@PORT@@/` returns 200 with app HTML. Stop with `just stop`.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
