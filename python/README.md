# Python Nix Template

A minimal Python application template using Nix.

## Features

- Fully managed by Nix (`buildPythonApplication`)
- `pyproject.toml` based build (setuptools)
- Development shell with dependencies available

## Setup

```bash
direnv allow
```

## Running the application

```bash
nix run
```

## Adding dependencies

1. Add your dependencies to the `dependencies` list in `flake.nix`
2. Add your dependencies to `pyproject.toml` (optional but good practice)
3. Run `direnv reload` or `nix develop`
