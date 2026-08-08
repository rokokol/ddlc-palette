<div align="center">

# DDLC palette

**The Doki Doki Literature Club colours, measured off the official site** （´ω｀♡%）

![source](https://img.shields.io/badge/source-ddlc.moe-FF80C0?style=flat)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/code-MIT-3DA639?style=flat)](LICENSE)
[![check](https://github.com/rokokol/ddlc-palette/actions/workflows/check.yml/badge.svg)](https://github.com/rokokol/ddlc-palette/actions/workflows/check.yml)

<img src="dist/palette.svg" alt="the palette" width="680"/>

[Русский](README.ru.md)

</div>

One source of truth for every DDLC-themed thing I build, so the same pink does not get eyeballed a fifth time. [`palette.json`](palette.json) is that source; everything in [`dist/`](dist) is generated from it and committed, so a consumer without Nix just reads a file

## Where the numbers come from

Not from a screenshot and not from taste — from [ddlc.moe](https://ddlc.moe/) itself:

| | what was read |
| --- | --- |
| **interface** | `main.css` — the divider, the button and its hover, the link colour, the dark footer |
| **dot**, **paper** | `images/tilebg.png`, the site's own background tile: 200×200, dots of radius 40 on a half-step grid, `#FFDBF0` on white |
| **characters** | the `sticker_?.png` sprites, most frequent hair colour across the top of each head |
| **accents** | `images/screen5.png`, the two tones of Sayori's bow — the site ships no other strong red |

Nothing here is invented

Each entry in `palette.json` carries its own `where` and `source`, so nothing in here is unattributable

## Use it

**Nix.** The flake exposes the palette as plain data — no module, no options, nothing to enable:

```nix
{
  inputs.ddlc-palette.url = "github:rokokol/ddlc-palette";

  # inputs.ddlc-palette.lib.palette.plum  ->  "#BB5599"
  # inputs.ddlc-palette.lib.bare.plum     ->  "BB5599"   (hyprland, hyprlock, mako)
  # inputs.ddlc-palette.lib.annotated     ->  grouped, with provenance
}
```

**Anything else.** Pick the file that fits:

| file | shape |
| --- | --- |
| `dist/palette.css` | `:root { --ddlc-plum: #BB5599; … }` |
| `dist/palette.nix` | `{ plum = "#BB5599"; … }` |
| `dist/palette.sh` | `DDLC_PLUM='#BB5599'` — source it |
| `dist/palette.env` | `plum=BB5599` — bare hex, for configs that reject `#` |
| `dist/palette.svg` | the swatch card above |

## Re-reading the site

The provenance above is a claim until something reproduces it, so `canonize.sh` does:
it fetches `main.css`, the tile, the four sprites and a screenshot, measures every colour again and writes
`palette.json`. Running it against today's site reproduces every hex in this repository exactly

```sh
nix develop -c ./canonize.sh   # or: curl, jq, imagemagick, awk on PATH
./generate.sh
```

It refuses to guess: the site answers `200` with an HTML page for anything missing, so the script
checks `content-type` rather than the status code, and it aborts if a CSS rule it reads has lost its
colour. A monthly workflow runs it and fails if the site has drifted away from what is committed

## Changing a colour

Edit `palette.json` by hand for anything the site does not define, then:

```sh
./generate.sh          # needs jq
```

Commit both. CI rebuilds `dist/` and diffs it against what you committed, so the two cannot drift

## Used by

- [ddlc-sddm-theme](https://github.com/rokokol/ddlc-sddm-theme) — the login screen
- more of [rokokol/huix](https://github.com/rokokol/huix) as it gets split out: hyprlock, waybar, mako, rofi

## Credits

Doki Doki Literature Club is by [Team Salvato](https://teamsalvato.com/), and so are the colours as they appear on their site — this repository only writes them down. Unaffiliated with and not endorsed by them. The code is MIT
