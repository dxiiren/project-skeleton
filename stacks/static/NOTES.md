# Stack notes — static

> **TL;DR** — a static site served by Python's stdlib `http.server` via uv. No toolchain, no
> build; the only moving parts are the port and the docroot.

## Gotchas proven in the field

- **Docroot:** `@@DOCROOT@@` is usually `.`; if `index.html` lives in a subfolder, point
  there. The trailing `\.` in the serve path is EXPECTED — don't "fix" it.
- **`python -m http.server` serves `index.html` at `/` automatically** — probe either `/`
  or `/index.html`.
- **Explicit IPv4 bind:** the recipe binds `127.0.0.1` explicitly, so `http://127.0.0.1:@@PORT@@`
  URLs are correct here (unlike the node stacks).
- **External assets** (Google Fonts `@import` etc.) need internet; offline the page falls
  back to system fonts — expected, not a bug. Flag any NEW external URL in review.
- **No lint/test toolchain:** quality gates are the stdlib HTML parse + greps in
  `/lint-check` — do NOT introduce an npm toolchain just to lint one HTML file.
- **Boot-verify:** `just start`, then GET `/index.html` returns 200. Stop with `just stop`.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
