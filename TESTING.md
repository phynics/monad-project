# Testing Guide for Monad Assistant

This document outlines the testing strategy, tools, and commands for the Monad Assistant project.

## Overview

The project employs a multi-layered testing strategy:
1.  **Unit Tests (`MonadCoreTests`, `MonadServerTests`)**: Verify individual components, models, and services in isolation.
2.  **Integration Tests (`E2EIntegrationTests`)**: Verify the interaction between the gRPC server handlers and the persistence layer using an in-process server.
3.  **Fuzz Tests (`FuzzTests`, `MonadFuzzer`)**: Test resilience against malformed inputs.
4.  **Performance Tests (`BenchmarkTests`)**: Ensure critical paths meet latency requirements.

## Running Tests

### Standard Unit & Integration Tests
To run the standard test suite using Swift Package Manager:

```bash
swift test
```

This includes:
- Core logic tests
- Server handler logic tests
- E2E integration tests (using transient in-memory databases)
- Mock-based resilience tests

### Performance Benchmarks
To run only the performance benchmarks:

```bash
swift test --filter BenchmarkTests
```

### Fuzz Testing

#### Automated Fuzz Test Suite
We have a data-driven fuzz test suite that runs with standard `swift test`. This generates random/edge-case inputs for standard handlers:

```bash
swift test --filter FuzzTests
```

#### libFuzzer (Advanced)
We also support coverage-guided fuzzing via `libFuzzer`.

**Prerequisites:**
- A Swift toolchain that supports `-sanitize=fuzzer` (e.g., standard Linux Swift toolchains, or specific nightly macOS toolchains). *Note: The default Xcode toolchain on macOS 14 does not fully support this yet.*

**Running:**
Use the provided Makefile command:
```bash
make fuzz
```

If you are on a system without `libFuzzer` support, this command may fail to link.

## UI Testing
UI behavior is primarily tested via ViewModels in `MonadCoreTests` (e.g., `ChatViewModelStateTests`). We validate state transitions, loading states, and error handling without launching a simulator.

## Code Coverage
To generate a code coverage report:

```bash
swift test --enable-code-coverage
```

## Continuous Integration
All tests are run automatically on CI. Ensure `swift test` passes locally before pushing.
