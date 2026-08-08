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
      groups = builtins.removeAttrs raw [ "meta" ];
    in
    {
      # The palette itself: { paper = "#FFFFFF"; ... } — one flat attrset, names unique across groups
      lib = {
        palette = builtins.foldl' (acc: g: acc // builtins.mapAttrs (_: v: v.hex) groups.${g}) { } (
          builtins.attrNames groups
        );

        # The same, grouped and with the provenance kept
        annotated = groups;

        meta = raw.meta;

        # Strip the "#" — hyprland, hyprlock and mako want bare hex
        bare = builtins.mapAttrs (_: v: builtins.substring 1 (builtins.stringLength v) v) self.lib.palette;
      };

      packages = forAllSystems (pkgs: {
        default = pkgs.runCommand "ddlc-palette" { } ''
          mkdir -p $out/share/ddlc-palette
          cp ${./palette.json} $out/share/ddlc-palette/palette.json
          cp -r ${./dist}/. $out/share/ddlc-palette/
        '';
      });

      # dist/ is committed so non-Nix consumers can just read a file; this proves it is current
      checks = forAllSystems (pkgs: {
        dist-is-current = pkgs.runCommand "dist-is-current" { nativeBuildInputs = [ pkgs.jq ]; } ''
          cp -r ${./.}/. work && chmod -R +w work
          cd work && bash generate.sh >/dev/null
          diff -r ${./dist} dist
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.jq
            pkgs.curl
            pkgs.imagemagick
            pkgs.gawk
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
