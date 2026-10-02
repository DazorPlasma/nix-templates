# Nix templates

Personal Nix flake templates for starting projects quickly.

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [direnv](https://direnv.net/) (recommended) for automatic `nix develop` / shell hooks

## Usage

Instantiate a template into a new directory:

```bash
# From a local checkout:
nix flake new -t path:/home/work/coding/nix-templates#rust-service my-app

# From inside this repo:
nix flake new -t .#rust-service my-app

# From a remote git URL (adjust host/path as needed):
# nix flake new -t git+ssh://git@example.com/you/nix-templates#rust-service my-app
```

Then `cd` into the new project, allow direnv if present (`direnv allow`), and follow that template’s README.

List available templates:

```bash
nix flake show
```

## Templates

| Template | Description |
|----------|-------------|
| `rust` | Rust toolchain-only development shell |
| `dioxus` | Dioxus desktop dependencies (Linux / macOS) |
| `bevy` | Bevy game engine deps (Wayland) |
| `rust-service` | Crane builds, Docker images, and `start` / `start debug` / `docs` / `full-test` |
| `python` | Minimal Python application using `buildPythonApplication` |

After scaffolding **`rust-service`**, see that project’s [README](./rust-service/README.md) for configuration, validation, and day-to-day commands.
