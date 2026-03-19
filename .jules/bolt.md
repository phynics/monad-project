## 2024-05-14 - Swift Compiler Crashes on Linux
**Learning:** The current Swift 6.2.3 compiler on Linux consistently crashes (Signal 11) when trying to compile `swift-algorithms`. This blocks local `swift test` execution.
**Action:** Always rely on static analysis and manual verification of code changes instead of local testing if blocked by this compiler issue.
