{
  pkgs,
  rustToolchain,
  apiPort,
}: let
  apiPortStr = toString apiPort;
  cargoRuntimeInputs = with pkgs; [
    rustToolchain
    pkg-config
    openssl
    stdenv.cc
  ];
  cargoBuildEnvironment = ''
    export OPENSSL_NO_VENDOR=1
    export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  '';

  requireSecrets = pkgs.writeShellScriptBin "app-require-secrets" ''
    set -euo pipefail

    if [ ! -f secrets.json ]; then
      echo "secrets.json not found. Copy secrets.json.sample to secrets.json." >&2
      exit 1
    fi

    if [ ! -r secrets.json ]; then
      echo "secrets.json is not readable by the current user." >&2
      exit 1
    fi
  '';

  loadImages = pkgs.writeShellScriptBin "app-load-images" ''
    set -euo pipefail

    ${requireSecrets}/bin/app-require-secrets

    profile="''${1:-all}"
    state_dir=".direnv/app-images"
    mkdir -p "$state_dir"

    build_and_load() {
      local attribute="$1"
      local tag="$2"
      local output
      local image_id
      local state_file="$state_dir/$attribute"

      # nom (nix-output-monitor) shows live build progress; store path stays on stdout.
      output="$(${pkgs.nix-output-monitor}/bin/nom build ".#$attribute" --no-link --print-out-paths)"

      # Docker tags are global to the daemon, so another checkout can replace
      # this tag while leaving this checkout's state file untouched. Remember
      # and compare the image ID as well as the Nix output path.
      image_id="$(${pkgs.docker}/bin/docker image inspect --format '{{.Id}}' "$tag" 2>/dev/null || true)"
      if [ -n "$image_id" ] \
        && [ -f "$state_file" ] \
        && [ "$(cat "$state_file")" = "$(printf '%s\n%s' "$output" "$image_id")" ]; then
        echo "Image $tag is up to date"
        return 0
      fi

      echo "Loading $tag from $output"
      ${pkgs.docker}/bin/docker load < "$output"
      image_id="$(${pkgs.docker}/bin/docker image inspect --format '{{.Id}}' "$tag")"
      printf '%s\n%s\n' "$output" "$image_id" > "$state_file"
    }

    case "$profile" in
      release)
        build_and_load "docker" "app:release"
        ;;
      debug)
        build_and_load "docker-debug" "app:debug"
        ;;
      all)
        build_and_load "docker" "app:release"
        build_and_load "docker-debug" "app:debug"
        ;;
      *)
        echo "usage: app-load-images [release|debug|all]" >&2
        exit 1
        ;;
    esac
  '';

  writeComposeOverride = pkgs.writeShellScriptBin "app-write-compose-override" ''
    set -euo pipefail
    override_file="''${1:?override file path required}"
    host_uid="$(${pkgs.coreutils}/bin/id -u)"
    host_gid="$(${pkgs.coreutils}/bin/id -g)"
    if [ "$host_uid" = 0 ]; then
      echo "start must run as a non-root user so the container can read secrets.json without broadening its permissions." >&2
      exit 1
    fi
    cat > "$override_file" <<EOF
    services:
      api:
        user: "$host_uid:$host_gid"
        ports:
          - "127.0.0.1:${apiPortStr}:${apiPortStr}"
        volumes:
          - ./secrets.json:/run/secrets/app.json:ro
        healthcheck:
          test: ["CMD", "${pkgs.curl}/bin/curl", "--fail", "--silent", "--show-error", "--output", "/dev/null", "http://127.0.0.1:${apiPortStr}/health"]
          interval: 2s
          timeout: 2s
          retries: 30
          start_period: 5s
      api-debug:
        user: "$host_uid:$host_gid"
        ports:
          - "127.0.0.1:${apiPortStr}:${apiPortStr}"
        volumes:
          - ./secrets.json:/run/secrets/app.json:ro
        healthcheck:
          test: ["CMD", "${pkgs.curl}/bin/curl", "--fail", "--silent", "--show-error", "--output", "/dev/null", "http://127.0.0.1:${apiPortStr}/health"]
          interval: 2s
          timeout: 2s
          retries: 30
          start_period: 5s
    EOF
  '';

  start = pkgs.writeShellScriptBin "start" ''
    set -euo pipefail
    profile="''${1:-release}"
    ${requireSecrets}/bin/app-require-secrets
    ${loadImages}/bin/app-load-images "$profile"

    override_file="$(mktemp)"
    trap 'rm -f "$override_file"' EXIT
    ${writeComposeOverride}/bin/app-write-compose-override "$override_file"

    case "$profile" in
      release) opposite_service=api-debug ;;
      debug) opposite_service=api ;;
      *) echo "usage: start [release|debug]" >&2; exit 1 ;;
    esac

    # Both profiles publish the same host port, so stop the other profile
    # before starting this one.
    ${pkgs.docker}/bin/docker compose --profile "*" \
      -f docker-compose.yml -f "$override_file" stop "$opposite_service"

    if ${pkgs.docker}/bin/docker compose --profile "$profile" \
      -f docker-compose.yml -f "$override_file" up -d --wait --wait-timeout 60; then
      compose_status=0
    else
      compose_status=$?
    fi
    exit "$compose_status"
  '';

  stop = pkgs.writeShellScriptBin "stop" ''
    set -euo pipefail
    exec ${pkgs.docker}/bin/docker compose --profile "*" stop
  '';

  full-test = pkgs.writeShellApplication {
    name = "full-test";
    runtimeInputs = cargoRuntimeInputs;
    text = ''
      ${cargoBuildEnvironment}

      docker="${pkgs.docker}/bin/docker"
      pgrep="${pkgs.procps}/bin/pgrep"

      refuse() {
        echo "$1" >&2
        exit 1
      }

      running_compose="$("$docker" compose --profile "*" ps -q --status running 2>/dev/null || true)"
      if [ -n "$running_compose" ]; then
        echo "Docker Compose services are running; stopping them first..."
        ${stop}/bin/stop
      fi

      if "$pgrep" -af . 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -E \
          'target/.*/app([[:space:]]|$)|[/ ]cargo([0-9.-]*)?[[:space:]]+test([[:space:]]|$)' \
        | ${pkgs.gnugrep}/bin/grep -vE 'full-test|grep -E' \
        >/dev/null; then
        refuse "A cargo test or app process is already running. Stop it before re-running."
      fi

      echo "Running cargo test..."
      exec cargo test "$@"
    '';
  };

  start-debug = pkgs.writeShellScriptBin "start-debug" ''
    exec ${start}/bin/start debug
  '';

  logs = pkgs.writeShellScriptBin "logs" ''
    set -euo pipefail

    docker="${pkgs.docker}/bin/docker"

    if [ "$#" -eq 0 ]; then
      exec "$docker" compose --profile "*" logs -f
    fi

    if [ "$1" = "api" ]; then
      shift
      exec "$docker" compose --profile release logs -f api "$@"
    fi

    if [ "$1" = "debug" ] && [ "''${2:-}" = "api" ]; then
      shift 2
      exec "$docker" compose --profile debug logs -f api-debug "$@"
    fi

    echo "usage: logs | logs api | logs debug api" >&2
    exit 1
  '';

  logs-api = pkgs.writeShellScriptBin "logs-api" ''
    exec ${logs}/bin/logs api "$@"
  '';

  logs-debug-api = pkgs.writeShellScriptBin "logs-debug-api" ''
    exec ${logs}/bin/logs debug api "$@"
  '';

  docs = pkgs.writeShellApplication {
    name = "docs";
    runtimeInputs =
      cargoRuntimeInputs
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.xdg-utils];
    text = ''
      ${cargoBuildEnvironment}
      exec cargo doc --no-deps --document-private-items --open "$@"
    '';
  };
in {
  inherit loadImages start start-debug stop full-test logs logs-api logs-debug-api docs;
}
