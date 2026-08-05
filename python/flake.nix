{
  description = "Python application development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pythonPackages = pkgs.python3Packages;

        # Define dependencies here
        dependencies = with pythonPackages; [
          # e.g., requests, numpy
        ];

        # Define the application
        app = pythonPackages.buildPythonApplication {
          pname = "app";
          version = "0.1.0";
          pyproject = true;
          src = ./.;

          build-system = with pythonPackages; [
            setuptools
          ];

          dependencies = dependencies;

          # Optional: testing configuration
          nativeCheckInputs = with pythonPackages; [
            pytestCheckHook
          ];
          
          # By default we don't have tests, disable to avoid errors
          doCheck = false;
        };
      in
      {
        packages.default = app;
        packages.app = app;

        devShells.default = pkgs.mkShell {
          # Include the application dependencies in the shell
          inputsFrom = [ app ];

          # Add development-only tools here
          packages = with pkgs; [
            # Development tools
            pythonPackages.pytest
            pythonPackages.black
            pythonPackages.mypy
          ];
        };
      }
    );
}
