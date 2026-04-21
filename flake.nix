{
  description = "tmux-which-key plugin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.default = pkgs.tmuxPlugins.mkTmuxPlugin {
        pluginName = "tmux-which-key";
        version = "2026-04-21";
        src = ./.;
        rtpFilePath = "which-key.tmux";
      };
    };
}
