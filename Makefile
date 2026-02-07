.PHONY: help build clean test run-server run-cli server run rebuild query command

# Default target
help:
	@echo "Monad - Development Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build                 Build the project"
	@echo "  make run-server            Run the server"
	@echo "  make run-cli               Interactive chat mode"
	@echo "  make query Q=\"question\"    Quick query"
	@echo "  make command T=\"task\"      Generate shell command"
	@echo "  make clean                 Clean build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  make test                  Run tests"
	@echo "  make rebuild               Clean and rebuild"
	@echo ""
	@echo "Environment Variables:"
	@echo "  MONAD_VERBOSE=true         Enable verbose logging"
	@echo "  MONAD_API_KEY=...          Set API key"

# Build the project
build:
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

# Run the CLI (interactive chat)
run-cli:
	@echo "Running MonadCLI..."
	@MONAD_API_KEY=monad-secret swift run MonadCLI $(ARGS)

# Quick query
query:
	@MONAD_API_KEY=monad-secret swift run MonadCLI query $(Q)

# Generate command
command:
	@MONAD_API_KEY=monad-secret swift run MonadCLI command $(T)

# Run tests
test:
	@echo "Running tests..."
	@swift test

# Quick rebuild
rebuild: clean build

# Convenience aliases
run: run-cli
server: run-server


# Install CLI
install:
	@echo "Installing MonadCLI..."
	@swift build -c release
	@cp -f .build/release/MonadCLI /usr/local/bin/monad

# Lint project
lint:
	@echo "Linting..."
	@swiftlint lint --strict --quiet
