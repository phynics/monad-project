## 2025-02-09 - VectorMath optimizations for query magnitudes

**Learning:** When performing semantic search loops, calculating vector similarity can be bottlenecked by redundant magnitude calculations on the query vector.
**Action:** Overload the `cosineSimilarity` function to accept a pre-calculated magnitude for the query vector, and use this overload in linear scan or ranking loops (`MemoryRepository.searchMemories` and `ContextRanker.rankMemories`).
