{
  description = "Monad Project Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        darwinFrameworks = if pkgs.stdenv.isDarwin then with pkgs.darwin.apple_sdk.frameworks; [
          Foundation
          Security
          SystemConfiguration
          CoreServices
          CoreFoundation
        ] else [];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gnumake
            sqlite
            # On macOS, we often rely on Xcode's Swift, but we can include 'swift' from nix.
            # Commenting out explicit 'swift' on Darwin to avoid conflicts if Xcode is preferred
            # or if nixpkgs swift is broken. 
            # (pkgs.lib.optionals (!pkgs.stdenv.isDarwin) [ swift ]) 
            swift
          ] ++ darwinFrameworks;

          shellHook = ''
            echo "Welcome to Monad Project Dev Shell"
            echo "Run 'make run-server' to start the server."
            echo "Run 'make run-cli' to start the CLI."
          '';
        };
      }
    );
}
