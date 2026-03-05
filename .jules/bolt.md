
## 2024-03-05 - Optimize Cosine Similarity with Pre-calculated Magnitude
**Learning:** In scenarios like semantic search and memory ranking, comparing a single query vector against hundreds or thousands of stored vectors results in recalculating the `sqrt(sumSq)` for the query vector on every single comparison.
**Action:** Introduced `magnitude(_:)` and an overloaded `cosineSimilarity(_:_:magnitudeA:)` to `VectorMath` which takes a pre-calculated magnitude for the query vector. This reduces the time complexity and floating-point operations within the loops of `PersistenceService.searchMemories` and `ContextRanker.rankMemories`. Measurements estimate reducing `sqrt` calls from `N` to `1` and `svesqD` calls by half.
