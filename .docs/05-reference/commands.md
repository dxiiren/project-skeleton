# Commands — @@PROJECT_TITLE@@

> **TL;DR** — run `just` with no arguments to list every recipe. This page explains each
> one and when to reach for it.

## Recipes

| Recipe | What it does | When |
| --- | --- | --- |
[GROUND: one row per recipe in THIS justfile (read it — don't guess), including the
claudex/claudeo/claudeh tail. Keep this table in sync with the justfile whenever a
recipe is added or removed.]

## Guards

The `[private] _require-*` recipes fail fast with a "run setup.ps1 first" message when a
required tool is missing — you never see them in `just --list`, but every recipe that
needs a tool depends on one.

## Related docs

| Doc | Why |
| --- | --- |
| [workflow.md](../03-development/workflow.md) | How the recipes fit the daily loop |
| [stack-notes.md](stack-notes.md) | Why some recipes look the way they do |
