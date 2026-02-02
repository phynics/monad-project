.PHONY: help generate build clean test open install-deps spm-build spm-test run server

# Default target
help:
	@echo "Monad - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install-deps    Install development dependencies"
	@echo "  make generate        Generate Xcode project from project.yml"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build           Build the server with Xcode"
	@echo "  make run-server      Build and run the server"
	@echo "  make run-cli         Build and run the CLI"
	@echo "  make clean           Clean build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  make open            Open project in Xcode"
	@echo "  make test            Run tests with Xcode"
	@echo ""
	@echo "Swift Package Manager:"
	@echo "  make spm-build       Build with Swift Package Manager"
	@echo "  make spm-test        Run tests with Swift Package Manager"
	@echo "  make spm-server      Run server with Swift Package Manager"
	@echo "  make spm-cli         Run CLI with Swift Package Manager"

# Install dependencies
install-deps:
	@echo "Installing development dependencies..."
	@which xcodegen > /dev/null || brew install xcodegen
	@echo "Dependencies installed!"

# Generate Xcode project
generate:
	@echo "Generating Xcode project..."
	@xcodegen generate
	@echo "Project generated at MonadProject.xcodeproj"

# Build the server
build: generate
	@echo "Building MonadServer..."
	@xcodebuild -project MonadProject.xcodeproj \
		-scheme MonadServer \
		-configuration Debug \
		build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf DerivedData
	@rm -rf .build
	@rm -rf build
	@echo "Clean complete!"

# Run the server
run-server: build
	@echo "Running MonadServer..."
	@"$(shell find ~/Library/Developer/Xcode/DerivedData -name "MonadServer" -type f -perm +111 -print -quit)"

# Run the CLI
run-cli: build
	@echo "Running MonadCLI..."
	@"$(shell find ~/Library/Developer/Xcode/DerivedData -name "monad" -type f -perm +111 -print -quit)" $(ARGS)

# Open in Xcode
open: generate
	@echo "Opening in Xcode..."
	@open MonadProject.xcodeproj

# Run tests with Xcode
test: generate
	@echo "Running tests..."
	@xcodebuild -project MonadProject.xcodeproj \
		-scheme MonadServer \
		-configuration Debug \
		test

# Swift Package Manager commands
spm-build:
	@echo "Building with Swift Package Manager..."
	@swift build

spm-test:
	@echo "Running tests with Swift Package Manager..."
	@swift test

spm-server:
	@echo "Running server with Swift Package Manager..."
	@swift run MonadServer

spm-cli:
	@echo "Running CLI with Swift Package Manager..."
	@swift run MonadCLI $(ARGS)

# Quick rebuild
rebuild: clean build

# Convenience aliases (use SPM directly)
run:
	@swift run MonadCLI $(ARGS)

server:
	@swift run MonadServer
