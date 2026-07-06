{
  description = "dioxus development environment";

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

        # Linux-specific dependencies for Dioxus Desktop (Tauri/Wry underneath)
        linuxDeps = with pkgs;
          lib.optionals stdenv.isLinux [
            glib
            gtk3
            libsoup_3
            webkitgtk_4_1
            libxdo
          ];

        # macOS-specific dependencies for Dioxus Desktop
        darwinDeps = with pkgs.darwin.apple_sdk.frameworks;
          lib.optionals pkgs.stdenv.isDarwin [
            Security
            SystemConfiguration
            WebKit
            AppKit
            CoreGraphics
            CoreServices
            Foundation
          ];
      in {
        devShells.default = pkgs.mkShell {
          # Tools needed at build time
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          buildInputs = with pkgs;
            [
              rustToolchain
              dioxus-cli
              openssl
            ]
            ++ linuxDeps
            ++ darwinDeps;

          env = {
            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";

            # Required for Linux Desktop apps to find dynamic libraries at runtime
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs;
              [
                libGL
                libxkbcommon
                wayland
              ]
              ++ linuxDeps);
          };
        };
      }
    );
}
