# app

Minimal Rust HTTP service scaffolded from the `rust-service` Nix template.

Images are built with Nix `dockerTools` (store layers on scratch — not Ubuntu/Alpine). Non-secret settings come from `config.nix`; secrets are mounted at runtime and never enter the Nix store.

## Prerequisites

- Nix with flakes
- direnv (recommended)
- Docker (for `start` / compose)

```bash
direnv allow
cp secrets.json.sample secrets.json
```

## Run

```bash
start          # release image + compose profile
start debug    # debug image (or: start-debug)
```

Then open `http://localhost:8080/health` (port from `config.nix`).

## Commands

| Command | Description |
|---------|-------------|
| `start` / `start debug` | Build Nix images, load into Docker, start compose |
| `start-debug` | Alias for `start debug` |
| `stop` | Stop compose services |
| `logs` / `logs api` / `logs debug api` | Follow logs |
| `full-test` | Stop stack if running, then `cargo test` |
| `docs` | Build and open rustdoc (`cargo doc --no-deps --document-private-items --open`) |
| `purge-all-data` | Wipe local Docker/Nix/build artifacts (asks for confirmation) |

Flake apps mirror these (`nix run .#start`, `nix run .#docs`, …).

## Configuration and validation

Non-secret settings live in [`config.nix`](./config.nix):

```nix
{
  server = {
    apiPort = 8080;
  };

  logging = {
    filter = "INFO";
  };
}
```

On every flake evaluation, `config.nix` is passed through [`nix/validate-config.nix`](./nix/validate-config.nix). That module:

- Requires exactly the attributes `server` and `logging`
- Checks `server.apiPort` is an integer in `1..65535`
- Checks `logging.filter` is a non-empty string
- **Throws at eval time** on missing, unexpected, or invalid values

Validated config is baked into images as `/etc/app/config.json`. A bad `config.nix` fails `nix build` / `start` before containers run.

Example validation failure:

```nix
# config.nix — invalid
{ server.apiPort = 99999; logging.filter = "INFO"; }
# → error: config.server.apiPort: expected an integer port in 1..65535, got 99999
```

Secrets stay in `secrets.json` (copy from `secrets.json.sample`). `start` only requires the file to exist; mount path in the container is `/run/secrets/app.json`.

## Rename `app` → your project

Replace the name in:

- `Cargo.toml` (`name`)
- `flake.nix` (description, package/app names if you rename outputs)
- `nix/rust.nix`, `nix/docker.nix`, `nix/shell-commands.nix` (binary, image tags, paths)
- `docker-compose.yml` (image names)
- Config/secrets paths under `/etc/…` and `/run/secrets/…` if you change them

A project-wide search for `app` (and `app-debug` / `app:release` / `app:debug`) is the safest approach.

## Sidecars

Compose ships **API only** (`api` / `api-debug`). Add Qdrant, Jaeger, Ollama, or other services in `docker-compose.yml` when your project needs them.
