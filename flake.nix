{
  description = "The Doki Doki Literature Club palette, measured off the official site";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      raw = builtins.fromJSON (builtins.readFile ./palette.json);
      groups = builtins.removeAttrs raw [
        "meta"
        "base16"
      ];
      # The one source of version: VERSION at the repo root, asserted against CHANGELOG by CI
      version = nixpkgs.lib.fileContents (
        builtins.path {
          name = "VERSION";
          path = ./VERSION;
        }
      );

      # Each piece isolated, so an edit to a document rebuilds nothing
      generator = builtins.path {
        name = "generate.sh";
        path = ./generate.sh;
      };
      paletteJson = builtins.path {
        name = "palette.json";
        path = ./palette.json;
      };
    in
    {
      # The palette itself: { paper = "#FFFFFF"; ... } — one flat attrset, with names
      # unique across groups
      lib = {
        inherit version;
        palette = builtins.foldl' (acc: g: acc // builtins.mapAttrs (_: v: v.hex) groups.${g}) { } (
          builtins.attrNames groups
        );

        # The same, grouped and with the provenance kept
        annotated = groups;

        inherit (raw) meta;

        # Strip the "#" — hyprland, hyprlock and mako want bare hex
        bare = builtins.mapAttrs (_: v: builtins.substring 1 (builtins.stringLength v) v) self.lib.palette;

        # Translucent, in the two spellings that exist. Both take the alpha as a "0".."1" string,
        # because toString 0.9 in Nix renders "0.900000":
        #   rgba.dot "0.9" -> "rgba(255, 219, 240, 0.9)"   GTK-CSS and rofi, which have no #RRGGBBAA
        #   argb.ink "0.25" -> "#40222222"                 Qt/QML, which spells the alpha first
        rgba = builtins.mapAttrs (
          _: hex: a:
          let
            byte = i: toString (nixpkgs.lib.fromHexString (builtins.substring i 2 hex));
          in
          "rgba(${byte 1}, ${byte 3}, ${byte 5}, ${a})"
        ) self.lib.palette;

        argb = builtins.mapAttrs (
          _: hex: a:
          let
            byte = builtins.floor (builtins.fromJSON a * 255 + 0.5);
          in
          "#${nixpkgs.lib.fixedWidthString 2 "0" (nixpkgs.lib.toHexString byte)}${builtins.substring 1 6 hex}"
        ) self.lib.palette;

        # { dark = { base00 = "#222222"; ... }; light = { ... }; } — the slots hold palette
        # key names in the JSON, so resolve them against the palette itself
        base16 = builtins.mapAttrs (_: slots: builtins.mapAttrs (_: name: self.lib.palette.${name}) slots) (
          builtins.removeAttrs raw.base16 [ "note" ]
        );

        # The rendered files as paths, so a consumer names a format instead of a filename and
        # copies one file into the store rather than the whole repository. Application themes
        # are not here — they live in their own repositories and read these schemes
        #   ddlc-themes for kitty, btop and friends, ddlc.nvim for the editor
        dist = {
          base16 = {
            light = ./dist/base16-ddlc-light.yaml;
            dark = ./dist/base16-ddlc-dark.yaml;
          };
          css = ./dist/palette.css;
          env = ./dist/palette.env;
          sh = ./dist/palette.sh;
          svg = ./dist/palette.svg;
        };
      };

      packages = forAllSystems (pkgs: {
        default =
          pkgs.runCommand "ddlc-palette-${version}"
            {
              meta = {
                description = "The Doki Doki Literature Club palette, measured off the official site";
                homepage = "https://github.com/rokokol/ddlc-palette";
                # MIT covers the generators; the colours themselves are Team Salvato's
                license = pkgs.lib.licenses.mit;
                # Plain data files — nothing here is built for a platform
                platforms = pkgs.lib.platforms.all;
              };
            }
            ''
              mkdir -p $out/share/ddlc-palette
              cp ${./palette.json} $out/share/ddlc-palette/palette.json
              cp -r ${./dist}/. $out/share/ddlc-palette/
            '';
      });

      # dist/ is committed so non-Nix consumers can just read a file; this proves it is current
      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        ddlc-palette = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      checks = forAllSystems (pkgs: {
        # The two files generate.sh reads, and no more. `${./.}` here tied this check to the
        # whole repository: an edit to the README changed its hash and rebuilt it.
        # generate.sh finds palette.json beside itself, so the two land in one directory
        dist-is-current = pkgs.runCommand "dist-is-current" { nativeBuildInputs = with pkgs; [ jq ]; } ''
          mkdir work && cd work
          install -m755 ${generator} generate.sh
          cp ${paletteJson} palette.json
          bash generate.sh >/dev/null
          diff -r ${./dist} dist
          touch $out
        '';

        # Provenance is the point of this repository, so an entry without it is a bug, not a
        # style lapse. "method" says how the hex was arrived at: read out of a CSS declaration,
        # the commonest pixel of a bucket, or the mean of one that has no commonest pixel. Three
        # methods and no fourth — every colour here is one canonize.sh re-reads
        palette-is-annotated =
          pkgs.runCommand "palette-is-annotated" { nativeBuildInputs = with pkgs; [ jq ]; }
            ''
              bad=$(jq -r '
                [ to_entries[]
                  | select(.key != "meta" and .key != "base16")
                  | .key as $g | .value | to_entries[] | .key as $k | .value as $v
                  | (["hex", "where", "source", "method"] - ($v | keys)) as $gone
                  | if $gone != [] then "\($g).\($k) is missing \($gone | join(", "))"
                    elif ($v.hex | test("^#[0-9A-F]{6}$") | not) then
                      "\($g).\($k) hex is \($v.hex)"
                    elif (["declared", "mode", "mean"] | index($v.method) | not) then
                      "\($g).\($k) method is \($v.method)"
                    else empty end
                ] | .[]
              ' ${./palette.json})
              if [ -n "$bad" ]; then
                echo "$bad" | sed 's/^/palette: /' >&2
                exit 1
              fi
              touch $out
            '';

        # The one shell file list lives here and nowhere else: CI's shell job is a fast
        # named status for this check, not a second copy of the commands
        scripts-lint =
          pkgs.runCommand "scripts-lint"
            {
              nativeBuildInputs = with pkgs; [
                shellcheck
                shfmt
              ];
            }
            ''
              cp ${./generate.sh} generate.sh
              cp ${./canonize.sh} canonize.sh
              shellcheck generate.sh canonize.sh
              shfmt -i 2 -ci -d generate.sh canonize.sh
              touch $out
            '';

        # A scheme is only usable if every slot is filled, no colour is spent twice and the
        # background-to-foreground ramp really is one
        base16-is-sane = pkgs.runCommand "base16-is-sane" { nativeBuildInputs = with pkgs; [ jq ]; } ''
          jq -r '
            ([to_entries[] | select(.key != "meta" and .key != "base16") | .value | to_entries[]]
              | from_entries) as $c
            | .base16 | to_entries[] | select(.key != "note") | .key as $v
            | .value | to_entries[] | select(.key | startswith("base"))
            | "\($v) \(.key) \(.value) \($c[.value].hex // "unmeasured")"
          ' ${./palette.json} | awk '
            function h2d(s,   i, n) {
              n = 0
              for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1
              return n
            }
            {
              variant = $1; slot = $2; name = $3; hex = $4
              if (hex !~ /^#[0-9A-F]{6}$/) fail(variant " " slot " (" name ") is " hex)
              if ((variant, hex) in seen)
                fail(variant " spends " hex " on both " seen[variant, hex] " and " slot)
              seen[variant, hex] = slot
              n[variant]++
              if (slot ~ /^base0[0-6]$/) {
                lum = (h2d(substr(hex, 2, 2)) * 299 + h2d(substr(hex, 4, 2)) * 587 + h2d(substr(hex, 6, 2)) * 114) / 1000
                step = lum - last[variant]
                # base01 fixes which way the ramp runs; light and dark go opposite ways
                if (slot == "base01") dir[variant] = step > 0 ? 1 : -1
                if (slot != "base00" && step * dir[variant] <= 0)
                  fail(variant " ramp turns back at " slot)
                last[variant] = lum
              }
            }
            function fail(msg) { print "base16: " msg > "/dev/stderr"; bad = 1 }
            END {
              for (v in n) if (n[v] != 16) fail(v " has " n[v] " slots, want 16")
              exit bad ? 1 : 0
            }
          '
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            curl
            imagemagick
            gawk
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
