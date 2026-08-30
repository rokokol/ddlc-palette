# Assets and third-party content

`LICENSE` (MIT) covers the **code** in this repository — `generate.sh`, `canonize.sh` and the Nix expressions. It does **not** cover the colours themselves, which are Team Salvato's as they appear on their site; this repository only writes them down

## Doki Doki Literature Club

Doki Doki Literature Club and Doki Doki Literature Club Plus are the property of [Team Salvato](https://teamsalvato.com/). This project is **unaffiliated with and not endorsed by Team Salvato**

The following are derived from official DDLC material:

| Path | What |
| --- | --- |
| `palette.json` | every `hex` in it is a value [ddlc.moe](https://ddlc.moe/) actually ships, read out of `main.css`, the `tilebg.png` background tile, the `sticker_?.png` sprites and two of the screenshots. `where`, `source` and `method` record which one and how — `declared` for a value written in the stylesheet, `mode` and `mean` for one measured off an image |
| `dist/` | `palette.json` rendered — the base16 schemes, the CSS variables, the shell env and `palette.svg`. Generated, and no colour in it is new |

No official artwork is bundled here. `dist/palette.svg` is a swatch sheet written by `generate.sh`, and the images the colours were measured from are not redistributed — `canonize.sh` fetches them at run time and keeps nothing

The `Doki` font family the themes downstream ask for is Team Salvato's and is **not** shipped here or anywhere in the family

Use here follows [Team Salvato's IP guidelines](https://teamsalvato.com/ip-guidelines): this is non-commercial fan content, nothing containing official assets is sold, and no claim of affiliation is made. If you reuse any of it, the same conditions apply to you

Team Salvato reserves the right to act on copyright or trademark infringement; nothing here grants a licence to their intellectual property
