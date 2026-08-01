# Stack notes — php-plain

> **TL;DR** — plain PHP served by `php -S` from a pinned PHP install. The server boots with
> no database; DB-backed pages error until MySQL is wired — that is a documented degraded
> state, not a broken kit.

## Gotchas proven in the field

- **Docroot:** `@@DOCROOT@@` is usually `.` — check where `index.php` lives. The resulting
  trailing `\.` in the serve path (`...\repo\.`) is EXPECTED — don't "fix" it.
- **MySQL-backed apps** (`mysqli` / `db_config.php`): the built-in server still boots
  without a DB — static/login pages serve fine (expect HTTP 200 + non-empty body), while
  DB-backed pages error. Document the MySQL requirement (host/db/user expected by
  `db_config.php`) in `.docs/02-setup/getting-started.md` +
  `.docs/06-troubleshooting/common-issues.md` and treat the project as running degraded
  until a local MySQL is provided. Never commit credentials.
- **No Composer/Node by default:** the setup script skips Composer and Node unless the repo
  actually has a `composer.json` / `package.json` (the Claude CLI install degrades to a
  warning when npm is absent).
- **Boot-verify:** `just start`, then GET `/` or `/index.php` returns 200 with a non-empty
  body. Stop with `just stop`.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
