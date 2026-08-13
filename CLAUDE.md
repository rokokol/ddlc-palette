# CLAUDE.md

## What this repo is

The colours every DDLC-themed thing I build reads, measured off [ddlc.moe](https://ddlc.moe) rather than eyeballed. `palette.json` is the source; everything in `dist/` is generated from it by `generate.sh` and committed, so a consumer without Nix reads a file. `canonize.sh` re-measures the site and rewrites `palette.json` in place — a weekly workflow runs it and opens a pull request when the site drifts

Consumers take `lib.palette`, `lib.bare`, `lib.rgba`, `lib.base16` and `lib.dist`: `ddlc-sddm-theme`, `ddlc-rofi-theme`, `ddlc-terminal-themes`, `ddlc.nvim`, `ddlc-hyprlock`, and `rokokol/huix` itself, which passes them down as `commonArgs.palette`

## Build / check

```sh
nix flake check          # dist/ is current, every colour is annotated, base16 is sane, shell is clean
nix eval --json .#lib.palette
nix develop -c ./generate.sh    # rewrite dist/ after editing palette.json
nix develop -c ./canonize.sh    # re-read the site (needs the network)
nix fmt -- --ci
```

## Layout

```
palette.json   the source: every colour, where it was measured and by which method
generate.sh    palette.json -> dist/, needs jq
canonize.sh    re-reads ddlc.moe and rewrites palette.json in place
dist/          the rendered forms, committed for consumers without Nix
```

## Changing a colour

Never by hand in `dist/` — edit `palette.json` and rerun `generate.sh`, then commit both. Every entry needs `hex`, `where`, `source` and a `method` out of `declared`, `mode`, `mean`; a check fails otherwise, because retracing a colour is the point of the repository

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date, tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
