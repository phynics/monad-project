.PHONY: help build clean test run server

# Default target
help:
	@echo "Monad - Development Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build           Build the project using SwiftPM"
	@echo "  make run-server      Run the server"
	@echo "  make run-cli         Run the CLI"
	@echo "  make clean           Clean build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  make test            Run tests"
	@echo ""
	@echo "Building MonadServer..."
	@swift build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf DerivedData
	@rm -rf .build
	@rm -rf build
	@echo "Clean complete!"

# Run the server
run-server:
	@echo "Running MonadServer..."
	@swift run MonadServer

# Run the CLI
run-cli:
	@echo "Running MonadCLI..."
	@swift run MonadCLI $(ARGS)

# Run tests
test:
	@echo "Running tests..."
	@swift test

# Quick rebuild
rebuild: clean build

# Convenience aliases
run: run-cli

server: run-server
