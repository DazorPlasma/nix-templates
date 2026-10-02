{
  pkgs,
  apiPort,
}: let
  apiPortStr = toString apiPort;

  requireSecrets = pkgs.writeShellScriptBin "app-require-secrets" ''
    set -euo pipefail

    if [ ! -f secrets.json ]; then
      echo "secrets.json not found. Copy secrets.json.sample to secrets.json." >&2
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
      local state_file="$state_dir/$attribute"

      # nom (nix-output-monitor) shows live build progress; store path stays on stdout.
      output="$(${pkgs.nix-output-monitor}/bin/nom build ".#$attribute" --no-link --print-out-paths)"

      if ${pkgs.docker}/bin/docker image inspect "$tag" >/dev/null 2>&1 \
        && [ -f "$state_file" ] \
        && [ "$(cat "$state_file")" = "$output" ]; then
        echo "Image $tag is up to date"
        return 0
      fi

      echo "Loading $tag from $output"
      ${pkgs.docker}/bin/docker load < "$output"
      printf '%s\n' "$output" > "$state_file"
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
    cat > "$override_file" <<EOF
    services:
      api:
        ports:
          - "${apiPortStr}:${apiPortStr}"
        volumes:
          - ./secrets.json:/run/secrets/app.json:ro
      api-debug:
        ports:
          - "${apiPortStr}:${apiPortStr}"
        volumes:
          - ./secrets.json:/run/secrets/app.json:ro
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

    if ${pkgs.docker}/bin/docker compose --profile "$profile" \
      -f docker-compose.yml -f "$override_file" up -d; then
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

  full-test = pkgs.writeShellScriptBin "full-test" ''
    set -euo pipefail

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

  purge-all-data = pkgs.writeShellScriptBin "purge-all-data" ''
    set -euo pipefail

    docker="${pkgs.docker}/bin/docker"

    echo "This will remove:"
    echo "  - containers, networks, and volumes managed by this Compose project"
    echo "  - target/ and .direnv/app-images/"
    echo "  - local Nix result symlinks (result and result-*)"
    echo
    echo "Docker images and Nix store paths are retained because their generic"
    echo "names and dependencies may be shared with other projects."
    echo
    echo "secrets.json and config.nix are NOT deleted."
    echo
    printf 'Type "yes" to continue: '
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
      echo "Aborted." >&2
      exit 1
    fi

    echo "Stopping compose services..."
    "$docker" compose --profile "*" stop >/dev/null 2>&1 || true
    "$docker" compose --profile "*" down -v --remove-orphans >/dev/null 2>&1 || true

    echo "Clearing project-local build caches..."
    rm -rf .direnv/app-images target
    rm -f result result-*

    echo "Done."
  '';

  docs = pkgs.writeShellScriptBin "docs" ''
    set -euo pipefail
    exec cargo doc --no-deps --document-private-items --open "$@"
  '';
in {
  inherit loadImages start start-debug stop full-test logs logs-api logs-debug-api purge-all-data docs;
}
