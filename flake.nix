{
  description = "tmux-which-key plugin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.tmuxPlugins.mkTmuxPlugin {
          pluginName = "tmux-which-key";
          version = "2026-04-21";
          src = ./.;
          rtpFilePath = "which-key.tmux";
        };
      });
    };
}
