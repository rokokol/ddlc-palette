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
# The sprites are too small to hold the poem notebook and the bow's second tone — these are
fetch images/screen2.png "$work/screen2.png" image/png
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

# "HEX x y" per pixel. Flattening onto white first: the RGB of a transparent pixel is arbitrary junk
pixels() {
  magick "$1" -background white -alpha remove -alpha off "${@:2}" txt:- |
    awk 'NR > 1 { split($1, p, /[,:]/); print toupper(substr($3, 2, 6)), p[1], p[2] }'
}

# The most frequent colour among the pixels an awk predicate accepts; -b also prints its
# bounding box. The predicate reads hex, r, g, b, mx, sat, lum, x and y, so every measurement
# below is one line: a region is named by what its colour looks like, not by a pinned crop.
#
# A flat fill has a commonest shade; a gradient does not, and no tie-break over equally frequent
# shades is a measurement — picking one is a coin toss dressed up as arithmetic. So when the top
# count is tied the answer is the mean of the whole bucket instead, and pick names the predicate
# that forked on stderr rather than quietly changing method
pick() {
  local box=0 args=()
  while [[ $1 == -v || $1 == -b ]]; do
    case $1 in
      -b)
        box=1
        shift
        ;;
      *)
        args+=(-v "$2")
        shift 2
        ;;
    esac
  done
  local test="$1"
  awk -v box="$box" -v test="$test" "${args[@]}" '
    function h2d(s,   i, n) {
      n = 0
      for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1
      return n
    }
    {
      hex = $1; x = $2 + 0; y = $3 + 0
      r = h2d(substr(hex, 1, 2)); g = h2d(substr(hex, 3, 2)); b = h2d(substr(hex, 5, 2))
      mx = r; if (g > mx) mx = g; if (b > mx) mx = b
      mn = r; if (g < mn) mn = g; if (b < mn) mn = b
      sat = mx ? (mx - mn) / mx : 0
      lum = (r * 299 + g * 587 + b * 114) / 1000
      if (!('"$test"')) next
      n[hex]++
      sr += r; sg += g; sb += b; total++
      if (!(hex in x0) || x < x0[hex]) x0[hex] = x
      if (!(hex in x1) || x > x1[hex]) x1[hex] = x
      if (!(hex in y0) || y < y0[hex]) y0[hex] = y
      if (!(hex in y1) || y > y1[hex]) y1[hex] = y
      if (bx0 == "" || x < bx0) bx0 = x
      if (bx1 == "" || x > bx1) bx1 = x
      if (by0 == "" || y < by0) by0 = y
      if (by1 == "" || y > by1) by1 = y
    }
    END {
      if (!total) exit 1
      # "for (h in n)" has no order, so count the winners rather than racing them
      for (h in n) if (n[h] > top) top = n[h]
      for (h in n) if (n[h] == top) tied++
      if (tied == 1) {
        for (h in n) if (n[h] == top) best = h
        print "#" best (box ? " " x0[best] " " x1[best] " " y0[best] " " y1[best] : "")
        exit 0
      }
      printf("canonize.sh: '\''%s'\'' has no commonest shade — %d tie at %d px, so all %d are averaged\n", \
        test, tied, top, total) > "/dev/stderr"
      printf "#%02X%02X%02X%s\n", int(sr / total + 0.5), int(sg / total + 0.5), int(sb / total + 0.5), \
        (box ? " " bx0 " " bx1 " " by0 " " by1 : "")
    }
  '
}

# Every pixel of the four stickers, for the colours the sprites share
sprites() {
  local c
  for c in s m n y; do pixels "$work/sticker_$c.png"; done
}

paper=$(css_color ".content")
blush=$(css_color ".banner-divider")
plum=$(css_color ".download-button ")
pink=$(css_color ".download-button:hover")
ink=$(css_color ".footer")
ash=$(css_color ".description-container hr")

# The dots: the tile is white with one colour on it, and the dot spans a full step
dot=$(pixels "$work/tilebg.png" | pick 'hex != "FFFFFF"')

read -r tile_w tile_h < <(magick identify -format '%w %h\n' "$work/tilebg.png")
# Dot radius from the top edge: its centre sits on the tile boundary, so the visible
# chord at y=0 is the full diameter
radius=$(pixels "$work/tilebg.png" |
  awk -v c="${dot#\#}" '$3 == 0 && $1 == c { n++ } END { print int(n / 2) }')

# Hair: the top of the head, ignoring white and the sticker outline
hair() {
  pixels "$work/sticker_$1.png" -crop '100%x22%+0+10%' +repage |
    pick 'hex !~ /^(FFFFFF|FFF[0-9A-F]{3})$/'
}
sayori=$(hair s)
monika=$(hair m)
natsuki=$(hair n)
yuri=$(hair y)

# Sayori's eyes are the only bright sky blue on her sprite; the uniform skirt is the same
# hue two stops darker, so one bucket split by brightness answers both
sayori_eye=$(pixels "$work/sticker_s.png" |
  pick 'b > r + 25 && b > g + 15 && sat > 0.30 && mx > 200')
skirt=$(sprites | pick 'b > r + 25 && b > g + 15 && sat > 0.30 && mx < 200')
# The jacket is the palette's only mid grey. Warm (r > b) keeps Monika's pale blue bow out
jacket=$(sprites | pick 'sat < 0.25 && lum > 120 && lum < 200 && r > b')
# Yuri's hair where the light does not reach: the deepest tone the sprites paint
yuri_shadow=$(sprites | pick 'b > g && r > g && lum < 70 && sat > 0.30')
# Monika's iris is a ramp of 64 shades over 68 pixels, so this is the one bucket that forks:
# no shade repeats more than twice and the answer is their mean. The saturation floor keeps the
# white it fades into from dragging that mean out of the green
monika_eye=$(pixels "$work/sticker_m.png" | pick 'g > r + 20 && g > b + 20 && sat > 0.60')

# The poem notebook holds the two tones no sprite does: a green dark enough to read on white,
# and the one blue mid-way enough to read on white and on ink alike
ribbon=$(pixels "$work/screen2.png" | pick 'g > r + 8 && g > b + 8 && lum < 120')
rule=$(pixels "$work/screen2.png" |
  pick 'b > r + 25 && b > g + 25 && sat > 0.30 && lum > 90 && lum < 160')

# Sayori's bow, the site's only strong red: the flat fill, then the shaded fold looked up
# inside the fill's own bounding box — so no crop is pinned to this screenshot
read -r bow bx0 bx1 by0 by1 < <(pixels "$work/screen5.png" |
  pick -b 'r > 120 && g < 110 && b < 120 && r - g > 80')
# The shade is a red as well, only a darker one — the two tests overlap on purpose
bow_shadow=$(pixels "$work/screen5.png" | pick \
  -v "fill=${bow#\#}" -v "bx0=$bx0" -v "bx1=$bx1" -v "by0=$by0" -v "by1=$by1" \
  'r > 60 && r - g > 60 && r - b > 40 && lum < 70 && hex != fill &&
   x >= bx0 && x <= bx1 && y >= by0 && y <= by1')

for v in paper blush plum pink ink ash dot sayori monika natsuki yuri \
  sayori_eye monika_eye skirt jacket yuri_shadow ribbon rule bow bow_shadow; do
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
  --arg sayoriEye "$sayori_eye" --arg monikaEye "$monika_eye" \
  --arg yuriShadow "$yuri_shadow" \
  --arg skirt "$skirt" --arg jacket "$jacket" \
  --arg ribbon "$ribbon" --arg rule "$rule" \
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
  | .characters.sayoriEye.hex = $sayoriEye
  | .characters.monikaEye.hex = $monikaEye
  | .characters.yuriShadow.hex = $yuriShadow
  | .uniform.skirt.hex = $skirt
  | .uniform.jacket.hex = $jacket
  | .notebook.ribbon.hex = $ribbon
  | .notebook.rule.hex = $rule
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
