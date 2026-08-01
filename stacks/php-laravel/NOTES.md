# Stack notes — php-laravel

> **TL;DR** — Laravel on Windows via a pinned PHP zip + Composer phar. Local DB is sqlite
> (never edit committed config), Vite assets must be built once before first boot, and
> Horizon/queue/broadcast features need the workarounds below.

## Gotchas proven in the field

- **Local DB is sqlite.** `just bootstrap` writes `DB_CONNECTION=sqlite` into the local
  `.env` and creates `database/database.sqlite`. NEVER edit the committed
  `config/database.php`, `.env.example` defaults, or migrations to make local boot work.
  If a migration uses MySQL-only DDL and fails on sqlite, document it in
  `.docs/06-troubleshooting/` and treat the app as degraded rather than editing migrations.
- **Laravel + Vite:** run `npm run build` once before the first boot — otherwise every page
  500s with "Vite manifest not found". `just bootstrap` already does this.
- **Pint:** `laravel/pint` ships in require-dev on every Laravel 12 scaffold. Add `lint` /
  `lint-fix` recipes (`& '{{php}}' vendor/bin/pint --test` / `... pint`) if the package is
  present — every stamped Laravel repo needed them.
- **Horizon:** `laravel/horizon` hard-requires `ext-pcntl` + `ext-posix`, which do not exist
  in Windows PHP — `composer install` fails the platform check. Fix in the justfile
  `bootstrap` recipe (NOT composer.json):
  `composer install --ignore-platform-req=ext-pcntl --ignore-platform-req=ext-posix`,
  and document that `php artisan horizon` cannot run on Windows (add a plain
  `queue:work` recipe instead).
- **Queue-backed features** (imports, jobs): add a `queue` recipe (`artisan queue:work`)
  and mention it in the README quick start — uploads/imports silently stall without a worker.
- **Broadcast features** (Pusher/Reverb) without shipped credentials: keep the local `.env`
  on `BROADCAST_CONNECTION=log`, exercise the non-realtime path, and document the wiring
  steps for anyone who wants realtime locally.
- **Boot-verify:** `just bootstrap` then `just start`, then
  `curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:@@PORT@@/` must print < 400
  (200/302 ok; 500 is a fail). Stop with `just stop`.

## Related docs

| Doc | Why |
| --- | --- |
| [conventions.md](conventions.md) | The invariants every kit file must keep |
| [commands.md](commands.md) | The just-recipe reference for this project |
