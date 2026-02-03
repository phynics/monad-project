{
  description = "SPM Project Dev Shell with Auto-Build";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          # Tools available in the shell
          packages = [
            pkgs.swift
            pkgs.swiftpm
            pkgs.apple-sdk_26
          ];

          # Run this every time you enter 'nix develop'
          shellHook = ''
            echo "🍎 Setting up Swift environment for macOS..."
            
            # 1. Build the project (allow network access for fetching deps)
            echo "🚀 Building targets..."
            swift build -c release
            
            # 2. Get the build path dynamically
            BUILD_PATH="$(swift build -c release --show-bin-path)"
            
            # 3. Add to PATH so you can run binaries by name
            export PATH="$BUILD_PATH:$PATH"
            
            echo "✅ Build complete. The following binaries are now in your PATH:"
            ls "$BUILD_PATH"
          '';
        };
      }
    );
}
