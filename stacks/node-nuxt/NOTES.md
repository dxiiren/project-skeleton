# Stack notes — node-nuxt

> **TL;DR** — Nuxt dev server on a pinned port. Same Windows `[::1]`-binding rule as Vite
> (always `localhost` in URLs), but Nuxt has NO `--strictPort` flag and `nuxt preview`
> takes its port from the `PORT` env var, not a CLI flag.

## Gotchas proven in the field

- **`localhost`, not `127.0.0.1`:** Node >= 17 binds `[::1]` only on Windows; an IPv4 probe
  gets connection-refused on a healthy server. Use `http://localhost:@@PORT@@` everywhere.
- **No `--strictPort`:** Nuxt doesn't support it; `--port {{port}}` alone is correct (the
  kit justfile already omits the flag). If the port is taken, Nuxt errors rather than
  hopping — acceptable.
- **`preview` reads `$env:PORT`:** the Nitro server behind `nuxt preview` ignores a
  `-- --port` passthrough. The kit recipe sets `$env:PORT='{{port}}'` first. `preview`
  needs a prior `just build` (Nitro bundle in `.output/`).
- **Vitest run-once:** force `--run` on any vitest-backed test script — bare vitest enters
  watch mode in a TTY and hangs the recipe. Split `test-unit`/`test-functional` recipes
  only if those npm scripts exist.
- **Recipe pruning:** keep only the recipes whose npm script exists in `package.json`.
- **Boot-verify:** `just install` + `just build` exit 0, then `just start`, then GET
  `http://localhost:@@PORT@@/` returns 200 with app HTML. Stop with `just stop`.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
