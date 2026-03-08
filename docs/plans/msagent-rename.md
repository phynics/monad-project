# Plan: Rename MSAgent → AgentTemplate

## Rename Mapping

### Types
| Old | New |
|-----|-----|
| `MSAgent` | `AgentTemplate` |
| `MSAgentRegistry` | `AgentTemplateRegistry` |
| `MSAgentExecutor` | `AgentTemplateExecutor` |
| `MSAgentStoreProtocol` | `AgentTemplateStoreProtocol` |
| `MSAgentAsTool` | `AgentTemplateAsTool` |
| `MSAgentAPIController` | `AgentTemplateAPIController` |
| `MSAgentRepository` | `AgentTemplateRepository` |
| `MSAgentRegistryKey` | `AgentTemplateRegistryKey` |
| `MSAgentExecutorKey` | `AgentTemplateExecutorKey` |
| `MSAgentStoreKey` | `AgentTemplateStoreKey` |
| `UnconfiguredMSAgentStore` | `UnconfiguredAgentTemplateStore` |
| `MockMSAgentStore` | `MockAgentTemplateStore` |

### Dependency properties (DependencyValues)
| Old | New |
|-----|-----|
| `msAgentRegistry: MSAgentRegistry` | `agentTemplateRegistry: AgentTemplateRegistry` |
| `msAgentExecutor: MSAgentExecutor` | `agentTemplateExecutor: AgentTemplateExecutor` |
| `msAgentStore: any MSAgentStoreProtocol` | `agentTemplateStore: any AgentTemplateStoreProtocol` |

### Methods on protocols / actors
| Old | New |
|-----|-----|
| `getMSAgent(id:)` | `getAgentTemplate(id:)` |
| `listMSAgents()` | `listAgentTemplates()` |
| `hasMSAgent(id:)` | `hasAgentTemplate(id:)` |
| `saveMSAgent(_:)` | `saveAgentTemplate(_:)` |
| `fetchMSAgent(id:)` | `fetchAgentTemplate(id:)` |
| `fetchMSAgent(key:)` | `fetchAgentTemplate(key:)` |
| `fetchAllMSAgents()` | `fetchAllAgentTemplates()` |
| `createMSAgentTable(in:)` | `createAgentTemplateTable(in:)` |

### API routes
| Old | New |
|-----|-----|
| `/msAgents` | `/agentTemplates` |
| `/api/msAgents` | `/api/agentTemplates` |
| `/api/msAgents/{id}` | `/api/agentTemplates/{id}` |

### Variables / local names (representative — all instances)
| Old | New |
|-----|-----|
| `msAgentRegistry` | `agentTemplateRegistry` |
| `msAgentExecutor` | `agentTemplateExecutor` |
| `msAgentStore` | `agentTemplateStore` |
| `msAgentController` | `agentTemplateController` |
| `msAgents` (array variable) | `agentTemplates` |
| `msAgentsMock` | `agentTemplatesMock` |

---

## NOT renamed (intentional)

- **Database table name** `"agent"` in `ModelConformances.swift` — already in migrations, changing it would require a migration.
- **`LaunchSubagentTool`** — separate concept (launching a subagent at runtime), not an MSAgent template.
- **`AgentInstance`**, **`AgentInstanceManager`** — already use the new "Agent" vocabulary.

---

## Steps

### Step 1 — File renames (git mv)
Use `git mv` to preserve history.

```
git mv Sources/MonadShared/SharedTypes/MSAgent.swift \
        Sources/MonadShared/SharedTypes/AgentTemplate.swift

git mv Sources/MonadCore/Services/MSAgents \
        Sources/MonadCore/Services/AgentTemplates
git mv Sources/MonadCore/Services/AgentTemplates/MSAgentRegistry.swift \
        Sources/MonadCore/Services/AgentTemplates/AgentTemplateRegistry.swift
git mv Sources/MonadCore/Services/AgentTemplates/MSAgentExecutor.swift \
        Sources/MonadCore/Services/AgentTemplates/AgentTemplateExecutor.swift

git mv Sources/MonadCore/Services/Database/MSAgentStoreProtocol.swift \
        Sources/MonadCore/Services/Database/AgentTemplateStoreProtocol.swift

git mv Sources/MonadCore/Services/Tools/MSAgent \
        Sources/MonadCore/Services/Tools/AgentTemplate
git mv Sources/MonadCore/Services/Tools/AgentTemplate/MSAgentAsTool.swift \
        Sources/MonadCore/Services/Tools/AgentTemplate/AgentTemplateAsTool.swift

git mv Sources/MonadServer/Controllers/MSAgentAPIController.swift \
        Sources/MonadServer/Controllers/AgentTemplateAPIController.swift
git mv Sources/MonadServer/Services/Database/Repositories/MSAgentRepository.swift \
        Sources/MonadServer/Services/Database/Repositories/AgentTemplateRepository.swift

git mv Sources/MonadClient/Client/MonadClient+MSAgents.swift \
        Sources/MonadClient/Client/MonadClient+AgentTemplates.swift

git mv Tests/MonadTestSupport/MockMSAgentStore.swift \
        Tests/MonadTestSupport/MockAgentTemplateStore.swift
git mv Tests/MonadCoreTests/MSAgentRegistryTests.swift \
        Tests/MonadCoreTests/AgentTemplateRegistryTests.swift
git mv Tests/MonadCoreTests/Models/MSAgents \
        Tests/MonadCoreTests/Models/AgentTemplates
git mv Tests/MonadCoreTests/Models/AgentTemplates/MSAgentModelTests.swift \
        Tests/MonadCoreTests/Models/AgentTemplates/AgentTemplateModelTests.swift
git mv Tests/MonadServerTests/MSAgentControllerTests.swift \
        Tests/MonadServerTests/AgentTemplateControllerTests.swift
```

### Step 2 — Edit renamed source files (type/method/property declarations)

**`Sources/MonadShared/SharedTypes/AgentTemplate.swift`**
- `struct MSAgent` → `struct AgentTemplate`
- `public extension MSAgent` → `public extension AgentTemplate`
- `MSAgent.fetchOne` → `AgentTemplate.fetchOne`

**`Sources/MonadCore/Services/AgentTemplates/AgentTemplateRegistry.swift`**
- `actor MSAgentRegistry` → `actor AgentTemplateRegistry`
- `getMSAgent(id:)` → `getAgentTemplate(id:)`
- `listMSAgents()` → `listAgentTemplates()`
- `hasMSAgent(id:)` → `hasAgentTemplate(id:)`
- All internal `MSAgent` type references → `AgentTemplate`
- `fetchMSAgent` → `fetchAgentTemplate`, `fetchAllMSAgents` → `fetchAllAgentTemplates`, `hasMSAgent` → `hasAgentTemplate` (calls on `persistence`)

**`Sources/MonadCore/Services/AgentTemplates/AgentTemplateExecutor.swift`**
- `struct MSAgentExecutor` → `struct AgentTemplateExecutor`
- All `MSAgent` type references → `AgentTemplate`

**`Sources/MonadCore/Services/Database/AgentTemplateStoreProtocol.swift`**
- `protocol MSAgentStoreProtocol` → `protocol AgentTemplateStoreProtocol`
- `saveMSAgent` → `saveAgentTemplate`
- `fetchMSAgent(id:)` → `fetchAgentTemplate(id:)`
- `fetchMSAgent(key:)` → `fetchAgentTemplate(key:)`
- `fetchAllMSAgents()` → `fetchAllAgentTemplates()`
- `hasMSAgent(id:)` → `hasAgentTemplate(id:)`
- All `MSAgent` type references → `AgentTemplate`

**`Sources/MonadCore/Services/Tools/AgentTemplate/AgentTemplateAsTool.swift`**
- `struct MSAgentAsTool` → `struct AgentTemplateAsTool`
- All `MSAgent` type/variable references → `AgentTemplate`

**`Sources/MonadCore/Dependencies/OrchestrationDependencies.swift`**
- `enum MSAgentRegistryKey` → `enum AgentTemplateRegistryKey`; `liveValue = MSAgentRegistry()` → `AgentTemplateRegistry()`
- `enum MSAgentExecutorKey` → `enum AgentTemplateExecutorKey`; update `liveValue`
- `var msAgentRegistry: MSAgentRegistry` → `var agentTemplateRegistry: AgentTemplateRegistry`
- `var msAgentExecutor: MSAgentExecutor` → `var agentTemplateExecutor: AgentTemplateExecutor`

**`Sources/MonadCore/Dependencies/StorageDependencies.swift`**
- `enum MSAgentStoreKey` → `enum AgentTemplateStoreKey`
- `var msAgentStore: any MSAgentStoreProtocol` → `var agentTemplateStore: any AgentTemplateStoreProtocol`
- `UnconfiguredMSAgentStore` → `UnconfiguredAgentTemplateStore`

**`Sources/MonadServer/Controllers/AgentTemplateAPIController.swift`**
- `struct MSAgentAPIController` → `struct AgentTemplateAPIController`
- All `msAgentRegistry` property/parameter → `agentTemplateRegistry`
- All `MSAgent` type refs → `AgentTemplate`
- All `listMSAgents()`/`getMSAgent()` calls → `listAgentTemplates()`/`getAgentTemplate()`

**`Sources/MonadServer/Services/Database/Repositories/AgentTemplateRepository.swift`**
- `actor MSAgentRepository: MSAgentStoreProtocol` → `actor AgentTemplateRepository: AgentTemplateStoreProtocol`
- All method renames (protocol conformance)
- All `MSAgent` type refs → `AgentTemplate`

**`Sources/MonadServer/Services/Database/ModelConformances.swift`**
- `extension MSAgent: FetchableRecord` → `extension AgentTemplate: FetchableRecord`
- `extension MSAgent { ... fetchDefault }` → `extension AgentTemplate`
- `MSAgent.fetchOne` → `AgentTemplate.fetchOne`
- `databaseTableName` stays `"agent"` (no change)

**`Sources/MonadClient/Client/MonadClient+AgentTemplates.swift`**
- `func listMSAgents()` → `func listAgentTemplates()`
- `func getMSAgent(id:)` → `func getAgentTemplate(id:)`
- Route strings: `/api/msAgents` → `/api/agentTemplates`
- Return types: `[MSAgent]` / `MSAgent?` → `[AgentTemplate]` / `AgentTemplate?`

### Step 3 — Edit callers / users

**`Sources/MonadCore/Services/Timeline/TimelineManager.swift`**
- `@Dependency(\.msAgentRegistry)` → `@Dependency(\.agentTemplateRegistry)`
- `var msAgentRegistry: MSAgentRegistry` → `var agentTemplateRegistry: AgentTemplateRegistry`
- All call sites `msAgentRegistry.getMSAgent` → `agentTemplateRegistry.getAgentTemplate`

**`Sources/MonadCore/Services/Tools/MSAgent/LaunchSubagentTool.swift`** (now `AgentTemplate/`)
- `msAgentRegistry` property + parameter → `agentTemplateRegistry`
- Calls `getMSAgent` → `getAgentTemplate`

**`Sources/MonadServer/MonadServerFactory.swift`**
- `msAgentStore` → `agentTemplateStore`, `MSAgentRepository` → `AgentTemplateRepository`
- `let msAgentExecutor = MSAgentExecutor(...)` → `let agentTemplateExecutor = AgentTemplateExecutor(...)`
- `let msAgentRegistry = ...` → (check if it exists and update)
- `BackgroundJobRunnerService(msAgentRegistry:, msAgentExecutor:)` → renamed labels
- `$0.msAgentRegistry` → `$0.agentTemplateRegistry`, `$0.msAgentExecutor` → `$0.agentTemplateExecutor`, `$0.msAgentStore` → `$0.agentTemplateStore`
- `msAgentController` var → `agentTemplateController`
- `MSAgentAPIController` → `AgentTemplateAPIController`
- Route string `/msAgents` → `/agentTemplates`

**`Sources/MonadServer/Services/BackgroundJobRunnerService.swift`**
- Properties `msAgentRegistry`, `msAgentExecutor` → renamed
- Init params → renamed
- Call sites `msAgentRegistry.getMSAgent` → `agentTemplateRegistry.getAgentTemplate`
- `msAgentExecutor.execute` → `agentTemplateExecutor.execute`

**`Sources/MonadServer/Services/Database/DatabaseSchema+Baseline.swift`**
- `createMSAgentTable` → `createAgentTemplateTable` (function name only; SQL table name `"agent"` unchanged)

**`Sources/MonadCore/Services/Agents/AgentInstanceManager.swift`**
- `MSAgent` type refs in parameter names/types → `AgentTemplate`

**`Sources/MonadCore/MonadCore.docc/MonadCore.md`**
- Comment updates

### Step 4 — Edit test files

**`Tests/MonadTestSupport/MockAgentTemplateStore.swift`**
- `class MockMSAgentStore: MSAgentStoreProtocol` → `MockAgentTemplateStore: AgentTemplateStoreProtocol`
- All `msAgents` → `agentTemplates`
- All method renames

**`Tests/MonadTestSupport/MockPersistenceService.swift`**
- `msAgentsMock` → `agentTemplatesMock`
- `var msAgents: [MSAgent]` → `var agentTemplates: [AgentTemplate]`
- Protocol method delegation renames

**`Tests/MonadCoreTests/AgentTemplateRegistryTests.swift`**
- Suite name + all type/method refs

**`Tests/MonadCoreTests/Models/AgentTemplates/AgentTemplateModelTests.swift`**
- Class name + all type refs

**`Tests/MonadServerTests/AgentTemplateControllerTests.swift`**
- Suite name + all type/method/route refs
- Route strings `/msAgents` → `/agentTemplates`

**`Tests/MonadClientTests/MonadClientErgonomicsTests.swift`**
- `listMSAgents()` → `listAgentTemplates()`
- `/api/msAgents` string check → `/api/agentTemplates`

**`Tests/MonadServerTests/JobControllerTests.swift`**
- `msAgentId` variable → `agentTemplateId` (or keep as `agentId`)

### Step 5 — CLAUDE.md + docs

**`CLAUDE.md`**:
- Replace all `MSAgent` references with `AgentTemplate`
- Update route paths

**`docs/INDEX.md`**, **`docs/AGENT.md`**, **`docs/ARCHITECTURE.md`**, **`docs/API_REFERENCE.md`**, **`docs/CONTEXT_SYSTEM.md`**:
- Replace all `MSAgent` references with `AgentTemplate`
- Update route paths `/msAgents` → `/agentTemplates`

### Step 6 — Build + test

```bash
swift build
swift test
```

---

## Risk notes

- **Database table name `"agent"` is unchanged** — no migration needed.
- **`LaunchSubagentTool.swift`** name stays; only internal variable/call-site renames.
- **API route change** (`/msAgents` → `/agentTemplates`) is a breaking change for existing clients — acceptable since this is an internal rename.
- The `persistenceService` aggregate protocol (which embeds `MSAgentStoreProtocol`) will also need its embedded methods renamed if it delegates directly. Check `PersistenceService` conformance.
