{
  pkgs,
  crane,
  src,
}: let
  craneLib = (crane.mkLib pkgs).overrideToolchain (_: pkgs.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml);

  cargoSrc = pkgs.lib.cleanSourceWith {
    inherit src;
    filter = path: type:
      (craneLib.filterCargoSources path type)
      || builtins.elem (baseNameOf path) [
        "README.md"
        "secrets.json.sample"
      ];
  };

  baseArgs = {
    src = cargoSrc;
    strictDeps = true;
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = with pkgs; [openssl];
    OPENSSL_NO_VENDOR = "1";
  };

  releaseArgs =
    baseArgs
    // {
      CARGO_PROFILE = "release";
    };

  debugArgs =
    baseArgs
    // {
      CARGO_PROFILE = "dev";
    };

  releaseCargoArtifacts = craneLib.buildDepsOnly releaseArgs;
  debugCargoArtifacts = craneLib.buildDepsOnly debugArgs;

  app = craneLib.buildPackage (
    releaseArgs
    // {
      cargoArtifacts = releaseCargoArtifacts;
      doCheck = false;
    }
  );

  app-debug = craneLib.buildPackage (
    debugArgs
    // {
      cargoArtifacts = debugCargoArtifacts;
      doCheck = false;
    }
  );
in {
  inherit app app-debug;
}
