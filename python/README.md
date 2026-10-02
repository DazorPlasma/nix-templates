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

1. Add runtime dependencies to the `dependencies` list in `flake.nix`.
2. For a distributable Python package, declare the same runtime dependencies in `[project].dependencies` in `pyproject.toml`; Nix dependencies define the Nix runtime closure, while `pyproject.toml` supplies package metadata.
3. Run `direnv reload` or `nix develop`.
