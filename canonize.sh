#!/usr/bin/env bash
# Re-read every measured colour from ddlc.moe and write it into palette.json.
# The provenance in the README is only a claim until this reproduces it
set -euo pipefail

site="${DDLC_SITE:-https://ddlc.moe}"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
json="$here/palette.json"

for tool in curl jq magick awk; do
  command -v "$tool" >/dev/null || {
    echo "canonize.sh: $tool is required — try nix develop" >&2
    exit 1
  }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() {
  local path="$1" dest="$2" type
  curl -sSL --fail --max-time 30 "$site/$path" -o "$dest"
  # The site answers 200 with an HTML page for anything missing, so trust the type, not the code
  type="$(curl -sSI --max-time 30 "$site/$path" | awk 'tolower($1)=="content-type:"{print tolower($2)}')"
  case "$type" in
    "$3"*) ;;
    *)
      echo "canonize.sh: $site/$path served '$type', expected $3 — the site moved" >&2
      exit 1
      ;;
  esac
}

fetch main.css "$work/main.css" text/css
fetch images/tilebg.png "$work/tilebg.png" image/png
for c in s m n y; do fetch "images/sticker_$c.png" "$work/sticker_$c.png" image/png; done

# #abc -> #AABBCC, #abcdef -> #ABCDEF
expand() {
  local h="${1#\#}"
  [[ ${#h} -eq 3 ]] && h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}"
  echo "#${h^^}"
}

# First colour declared inside a given CSS rule
css_color() {
  local selector="$1"
  local hex
  hex=$(awk -v sel="$selector" '
    index($0, sel) == 1 { inside = 1 }
    inside && match($0, /#[0-9a-fA-F]+/) {
      print substr($0, RSTART, RLENGTH); exit
    }
    inside && /}/ { inside = 0 }
  ' "$work/main.css")
  [[ -n $hex ]] || {
    echo "canonize.sh: no colour in rule '$selector' — the stylesheet changed" >&2
    exit 1
  }
  expand "$hex"
}

# Most frequent colour in a region, ignoring white and the sticker outline
dominant() {
  local file="$1" crop="$2"
  magick "$file" -crop "$crop" +repage -alpha off txt:- |
    awk -F'#' 'NR>1 {print substr($2,1,6)}' |
    awk '$1 !~ /^(FFFFFF|FFF[0-9A-F]{3})$/' |
    sort | uniq -c | sort -rn | awk 'NR == 1 { print "#" $2 }'
}

paper=$(css_color ".content")
blush=$(css_color ".banner-divider")
plum=$(css_color ".download-button ")
pink=$(css_color ".download-button:hover")
ink=$(css_color ".footer")
ash=$(css_color ".description-container hr")

# The dots: the tile is white with one colour on it, and the dot spans a full step
dot=$(magick "$work/tilebg.png" -alpha off txt:- |
  awk -F'#' 'NR>1 {print substr($2,1,6)}' | grep -v '^FFFFFF$' |
  sort | uniq -c | sort -rn | awk 'NR == 1 { print "#" $2 }')

read -r tile_w tile_h < <(magick identify -format '%w %h\n' "$work/tilebg.png")
# Dot radius from the top edge: its centre sits on the tile boundary, so the visible
# chord at y=0 is the full diameter
radius=$(magick "$work/tilebg.png" -alpha off txt:- |
  awk -F: -v c="${dot#\#}" '
    NR>1 {
      split($1, p, ",")
      if (p[2] == 0 && index($2, c)) n++
    }
    END { print int(n / 2) }
  ')

sayori=$(dominant "$work/sticker_s.png" "100%x22%+0+10%")
monika=$(dominant "$work/sticker_m.png" "100%x22%+0+10%")
natsuki=$(dominant "$work/sticker_n.png" "100%x22%+0+10%")
yuri=$(dominant "$work/sticker_y.png" "100%x22%+0+10%")

for v in paper blush plum pink ink ash dot sayori monika natsuki yuri; do
  [[ ${!v} =~ ^#[0-9A-F]{6}$ ]] || {
    echo "canonize.sh: $v came out as '${!v}'" >&2
    exit 1
  }
done

# No --sort-keys: the hand-made order carries meaning, and sorting buries the measured change
jq \
  --arg paper "$paper" --arg dot "$dot" --arg blush "$blush" --arg pink "$pink" \
  --arg plum "$plum" --arg ink "$ink" --arg ash "$ash" \
  --arg sayori "$sayori" --arg monika "$monika" --arg natsuki "$natsuki" --arg yuri "$yuri" \
  --arg tile "${tile_w}x${tile_h}" --arg radius "$radius" '
    .interface.paper.hex = $paper
  | .interface.dot.hex = $dot
  | .interface.blush.hex = $blush
  | .interface.pink.hex = $pink
  | .interface.plum.hex = $plum
  | .interface.ink.hex = $ink
  | .interface.ash.hex = $ash
  | .characters.sayori.hex = $sayori
  | .characters.monika.hex = $monika
  | .characters.natsuki.hex = $natsuki
  | .characters.yuri.hex = $yuri
  | .interface.dot.source = "images/tilebg.png, \($tile) tile, dots of radius \($radius) on a half-step offset grid"
  ' "$json" >"$work/palette.json"

if diff -q "$json" "$work/palette.json" >/dev/null; then
  echo "canonize.sh: palette.json already matches $site"
else
  cp "$work/palette.json" "$json"
  # dist/ is committed, so regenerate here — leaving it to the caller is what let it go stale
  "$here/generate.sh" >/dev/null
  echo "canonize.sh: updated palette.json and dist/ — review the diff"
fi
