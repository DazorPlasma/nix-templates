{
  pkgs,
  app,
  app-debug,
  runtimeConfigDir,
  apiPort,
}: let
  apiPortStr = toString apiPort;

  mkApiImage = {
    name,
    tag,
    package,
  }:
    pkgs.dockerTools.buildLayeredImage {
      inherit name tag;
      contents = with pkgs; [cacert openssl package runtimeConfigDir];
      config = {
        Cmd = [
          "${package}/bin/app"
          "--config"
          "/etc/app/config.json"
          "--secrets"
          "/run/secrets/app.json"
        ];
        ExposedPorts = {
          "${apiPortStr}/tcp" = {};
        };
      };
    };
in {
  docker = mkApiImage {
    name = "app";
    tag = "release";
    package = app;
  };

  docker-debug = mkApiImage {
    name = "app";
    tag = "debug";
    package = app-debug;
  };
}
