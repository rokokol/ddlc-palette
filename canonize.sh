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

# Prints "HEX method", and the bounding box after it under -b. The predicate reads hex, r, g, b,
# mx, sat, lum, x and y, so every measurement below is one line: a region is named by what its
# colour looks like, not by a pinned crop.
#
# A flat fill has a commonest shade; a gradient does not, and no tie-break over equally frequent
# shades is a measurement — picking one is a coin toss dressed up as arithmetic. So when the top
# count is tied the answer is the mean of the whole bucket instead. Which of the two ran is part
# of the result, not a detail: it travels into palette.json as "method" and onto stderr, so the
# method can neither be guessed from the hex nor change quietly
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
        print "#" best " mode" (box ? " " x0[best] " " x1[best] " " y0[best] " " y1[best] : "")
        exit 0
      }
      printf("canonize.sh: '\''%s'\'' has no commonest shade — %d tie at %d px, so all %d are averaged\n", \
        test, tied, top, total) > "/dev/stderr"
      printf "#%02X%02X%02X mean%s\n", int(sr / total + 0.5), int(sg / total + 0.5), int(sb / total + 0.5), \
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
read -r dot dot_by < <(pixels "$work/tilebg.png" | pick 'hex != "FFFFFF"')

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
read -r sayori sayori_by < <(hair s)
read -r monika monika_by < <(hair m)
read -r natsuki natsuki_by < <(hair n)
read -r yuri yuri_by < <(hair y)

# Sayori's eyes are the only bright sky blue on her sprite; the uniform skirt is the same
# hue two stops darker, so one bucket split by brightness answers both
read -r sayori_eye sayori_eye_by < <(pixels "$work/sticker_s.png" |
  pick 'b > r + 25 && b > g + 15 && sat > 0.30 && mx > 200')
read -r skirt skirt_by < <(sprites |
  pick 'b > r + 25 && b > g + 15 && sat > 0.30 && mx < 200')
# The jacket is the palette's only mid grey. Warm (r > b) keeps Monika's pale blue bow out
read -r jacket jacket_by < <(sprites | pick 'sat < 0.25 && lum > 120 && lum < 200 && r > b')
# Yuri's hair where the light does not reach: the deepest tone the sprites paint
read -r yuri_shadow yuri_shadow_by < <(sprites | pick 'b > g && r > g && lum < 70 && sat > 0.30')
# Monika's iris is a ramp of 64 shades over 68 pixels, so this is the one bucket that forks:
# no shade repeats more than twice and the answer is their mean. The saturation floor keeps the
# white it fades into from dragging that mean out of the green
read -r monika_eye monika_eye_by < <(pixels "$work/sticker_m.png" |
  pick 'g > r + 20 && g > b + 20 && sat > 0.60')

# The poem notebook holds the two tones no sprite does: a green dark enough to read on white,
# and the one blue mid-way enough to read on white and on ink alike
read -r ribbon ribbon_by < <(pixels "$work/screen2.png" | pick 'g > r + 8 && g > b + 8 && lum < 120')
read -r rule rule_by < <(pixels "$work/screen2.png" |
  pick 'b > r + 25 && b > g + 25 && sat > 0.30 && lum > 90 && lum < 160')

# Sayori's bow, the site's only strong red: the flat fill, then the shaded fold looked up
# inside the fill's own bounding box — so no crop is pinned to this screenshot
read -r bow bow_by bx0 bx1 by0 by1 < <(pixels "$work/screen5.png" |
  pick -b 'r > 120 && g < 110 && b < 120 && r - g > 80')
# The shade is a red as well, only a darker one — the two tests overlap on purpose
read -r bow_shadow bow_shadow_by < <(pixels "$work/screen5.png" | pick \
  -v "fill=${bow#\#}" -v "bx0=$bx0" -v "bx1=$bx1" -v "by0=$by0" -v "by1=$by1" \
  'r > 60 && r - g > 60 && r - b > 40 && lum < 70 && hex != fill &&
   x >= bx0 && x <= bx1 && y >= by0 && y <= by1')

# The one list of what was read: palette key, hex, and how it was arrived at. Names used to be
# spelled out three times over — here, in a validation loop and in the jq — and the third copy
# is what a new colour kept forgetting. "declared" is a literal lifted out of main.css, so
# there is no bucket and no method
measured="\
paper $paper declared
dot $dot $dot_by
blush $blush declared
pink $pink declared
plum $plum declared
ink $ink declared
ash $ash declared
sayori $sayori $sayori_by
monika $monika $monika_by
natsuki $natsuki $natsuki_by
yuri $yuri $yuri_by
monikaEye $monika_eye $monika_eye_by
sayoriEye $sayori_eye $sayori_eye_by
yuriShadow $yuri_shadow $yuri_shadow_by
jacket $jacket $jacket_by
skirt $skirt $skirt_by
ribbon $ribbon $ribbon_by
rule $rule $rule_by
bow $bow $bow_by
bowShadow $bow_shadow $bow_shadow_by"

while read -r key hex method; do
  [[ $hex =~ ^#[0-9A-F]{6}$ && $method =~ ^(declared|mode|mean)$ ]] || {
    echo "canonize.sh: $key came out as '$hex' by '$method'" >&2
    exit 1
  }
done <<<"$measured"

# No --sort-keys: the hand-made order carries meaning, and sorting buries the measured change.
# Merging per entry rather than assigning per path keeps the groups out of this script — a
# colour can be regrouped in the JSON without the canonizer knowing, as long as the key is unique
jq --argjson m "$(jq -Rn '[inputs | split(" ") | {(.[0]): {hex: .[1], method: .[2]}}] | add' \
  <<<"$measured")" \
  --arg tile "${tile_w}x${tile_h}" --arg radius "$radius" '
    [to_entries[] | select(.key != "meta" and .key != "base16") | .value | keys[]] as $known
  | (($m | keys) - $known) as $stray
  | if $stray != [] then
      "canonize.sh: measured \($stray | join(", ")) — no such entry in palette.json\n" | halt_error(1)
    else . end
  | with_entries(
      if .key == "meta" or .key == "base16" then .
      else .value |= with_entries(.value += ($m[.key] // {})) end)
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
