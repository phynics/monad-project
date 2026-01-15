# Jules Directives

## Environment Constraints
The current development environment lacks native Swift tools (`swift`, `xcodegen`, `xcodebuild`). Therefore, all building and testing **must** be performed using Docker.

## Testing Strategy
To run tests, use the provided helper script which utilizes `docker-compose.test.yml`.

### Running Tests
Execute the following command from the project root:

```bash
./bin/test-in-docker
```

This command will:
1. Spin up a `swift:6.0-jammy` container.
2. Mount the current directory.
3. Execute `swift test`.
4. Clean up the container upon completion.

### Manual Docker Execution
If you need to run specific commands or access the shell:

```bash
docker compose -f docker-compose.test.yml run --rm monad-test /bin/bash
```

## Test Harness
A dedicated test harness is located at `Tests/MonadCoreTests/JulesTestHarness.swift`. This harness validates:
- Persistence Service (Database interactions, Session lifecycle)
- Tool Executor (Tool execution, chaining)
- Streaming Coordinator (Stream parsing, Thinking tags, Tool calls)

Always verify changes by running the full test suite via Docker.
