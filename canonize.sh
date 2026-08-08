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
# The stickers are too small to hold the bow's second tone — the screenshot is
fetch images/screen5.png "$work/screen5.png" image/png

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

# Most frequent colour in a region, ignoring white and the sticker outline.
# Flattening onto white first: the RGB of a transparent pixel is arbitrary junk
dominant() {
  local file="$1" crop="$2"
  magick "$file" -background white -alpha remove -alpha off -crop "$crop" +repage txt:- |
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

# Sayori's bow, the only strong red the site ships: the flat fill, then the shaded fold
# looked up inside the fill's own bounding box — so no crop is pinned to this screenshot
read -r bow bow_shadow < <(magick "$work/screen5.png" -alpha off txt:- | awk '
  function h2d(s,   i, n) {
    n = 0
    for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1
    return n
  }
  # Ties broken by hex: "for (h in a)" has no order, and a canonizer may not be random
  function winner(a,   h, best) {
    for (h in a) if (best == "" || a[h] > a[best] || (a[h] == a[best] && h < best)) best = h
    return best
  }
  NR > 1 {
    hex = toupper(substr($3, 2, 6))
    r = h2d(substr(hex, 1, 2)); g = h2d(substr(hex, 3, 2)); b = h2d(substr(hex, 5, 2))
    split($1, p, ",")
    x = p[1] + 0; y = p[2] + 0
    if (r > 120 && g < 110 && b < 120 && r - g > 80) {
      fill[hex]++
      if (!(hex in x0) || x < x0[hex]) x0[hex] = x
      if (!(hex in x1) || x > x1[hex]) x1[hex] = x
      if (!(hex in y0) || y < y0[hex]) y0[hex] = y
      if (!(hex in y1) || y > y1[hex]) y1[hex] = y
    }
    # The shade is a red as well, only a darker one — the two tests overlap on purpose
    if (r > 60 && r - g > 60 && r - b > 40 && (r * 299 + g * 587 + b * 114) / 1000 < 70) {
      n++; dh[n] = hex; dx[n] = x; dy[n] = y
    }
  }
  END {
    f = winner(fill)
    for (i = 1; i <= n; i++)
      if (dh[i] != f && dx[i] >= x0[f] && dx[i] <= x1[f] && dy[i] >= y0[f] && dy[i] <= y1[f]) shade[dh[i]]++
    print "#" f, "#" winner(shade)
  }
')

for v in paper blush plum pink ink ash dot sayori monika natsuki yuri bow bow_shadow; do
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
  --arg bow "$bow" --arg bowShadow "$bow_shadow" \
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
  | .accents.bow.hex = $bow
  | .accents.bowShadow.hex = $bowShadow
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
