.PHONY: help generate build clean run test open install-deps

# Default target
help:
	@echo "Monad Assistant - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install-deps    Install development dependencies"
	@echo "  make generate        Generate Xcode project from project.yml"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build           Build the project"
	@echo "  make run             Build and run the app"
	@echo "  make clean           Clean build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  make open            Open project in Xcode"
	@echo "  make test            Run tests"
	@echo ""
	@echo "Package Manager:"
	@echo "  make spm-build       Build with Swift Package Manager"
	@echo "  make spm-run         Run with Swift Package Manager"

# Install dependencies
install-deps:
	@echo "📦 Installing development dependencies..."
	@which xcodegen > /dev/null || brew install xcodegen
	@echo "✅ Dependencies installed!"

# Generate Xcode project
generate:
	@echo "⚙️  Generating Xcode project..."
	@xcodegen generate
	@echo "✅ Project generated at MonadAssistant.xcodeproj"

# Build the project
build: generate
	@echo "🔨 Building MonadAssistant..."
	@xcodebuild -project MonadAssistant.xcodeproj \
		-scheme MonadAssistant \
		-configuration Debug \
		build

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@xcodebuild -project MonadAssistant.xcodeproj \
		-scheme MonadAssistant \
		clean
	@rm -rf DerivedData
	@rm -rf .build
	@echo "✅ Clean complete!"

# Run the application
run: build
	@echo "🚀 Running MonadAssistant..."
	@open -a "$(shell find ~/Library/Developer/Xcode/DerivedData -name "MonadAssistant.app" -print -quit)"

# Open in Xcode
open: generate
	@echo "📂 Opening in Xcode..."
	@open MonadAssistant.xcodeproj

# Run tests (when tests are added)
test: generate
	@echo "🧪 Running tests..."
	@xcodebuild -project MonadAssistant.xcodeproj \
		-scheme MonadAssistant \
		-configuration Debug \
		test

# Swift Package Manager commands (fallback)
spm-build:
	@echo "🔨 Building with Swift Package Manager..."
	@swift build

spm-run:
	@echo "🚀 Running with Swift Package Manager..."
	@swift run

# Quick rebuild
rebuild: clean build
