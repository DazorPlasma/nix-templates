{
  description = "bevy development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        # Bevy dependencies (Wayland only, no X11)
        linuxDeps = with pkgs;
          lib.optionals stdenv.isLinux [
            udev
            alsa-lib
            vulkan-loader
            wayland
            libxkbcommon
          ];
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs;
            [
              rustToolchain
              pkg-config
              openssl
            ]
            ++ linuxDeps;

          env = {
            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";

            # Allow Bevy to find dynamic libraries at runtime
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath linuxDeps;

            # Force Winit (Bevy's windowing library) to use Wayland
            WINIT_UNIX_BACKEND = "wayland";
          };
        };
      }
    );
}
