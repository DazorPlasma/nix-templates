{
  description = "app development and container builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        src = ./.;

        appConfig = import ./nix/validate-config.nix (import ./config.nix);

        rust = import ./nix/rust.nix {
          inherit pkgs crane src;
        };

        runtimeConfigDir = pkgs.writeTextDir "etc/app/config.json" (
          builtins.toJSON appConfig
        );

        dockerImages = import ./nix/docker.nix {
          inherit pkgs runtimeConfigDir;
          inherit (rust) app;
          inherit (rust) app-debug;
          inherit (appConfig.server) apiPort;
        };

        shellCommands = import ./nix/shell-commands.nix {
          inherit pkgs;
          inherit (appConfig.server) apiPort;
        };

        inherit (shellCommands) loadImages start start-debug stop full-test logs logs-api logs-debug-api purge-all-data docs;

        ciPackages = with pkgs; [
          rustToolchain
          pkg-config
          openssl
        ];

        # flake-utils.lib.mkApp omits meta, which `nix flake check` warns about.
        mkApp = drv: description:
          flake-utils.lib.mkApp {inherit drv;}
          // {
            meta = {inherit description;};
          };

        shellEnv = {
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          OPENSSL_NO_VENDOR = "1";
        };
      in {
        packages = {
          default = rust.app;
          inherit (rust) app;
          inherit (rust) app-debug;
          inherit (dockerImages) docker;
          inherit (dockerImages) docker-debug;
          runtime-config = runtimeConfigDir;
        };

        apps = {
          start = mkApp start "Build images and start the stack (release)";
          start-debug = mkApp start-debug "Build images and start the stack (debug)";
          stop = mkApp stop "Stop the running Docker containers";
          full-test = mkApp full-test "Stop stack if running, then cargo test";
          logs = mkApp logs "Follow logs for all services";
          logs-api = mkApp logs-api "Follow logs for the release API";
          logs-debug-api = mkApp logs-debug-api "Follow logs for the debug API";
          purge-all-data = mkApp purge-all-data "Remove Docker, Nix, and local build artifacts";
          docs = mkApp docs "Build and open rustdoc";
        };

        checks = {
          inherit (rust) app app-debug;
        };

        devShells = {
          default = pkgs.mkShell {
            packages =
              ciPackages
              ++ (with pkgs; [
                docker
                docker-compose
                nix-output-monitor
                loadImages
                start
                start-debug
                stop
                full-test
                logs
                logs-api
                logs-debug-api
                purge-all-data
                docs
              ]);

            env = shellEnv;
          };

          ci = pkgs.mkShell {
            packages = ciPackages;
            env = shellEnv;
          };
        };
      }
    );
}
