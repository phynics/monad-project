## 2024-05-24 - [VectorMath Linear Scan Optimization]
**Learning:** `VectorMath.cosineSimilarity` recalculated the query vector's magnitude inside inner loops (like `MemoryRepository.searchMemories` and `ContextRanker.rankMemories`), resulting in unnecessary computational overhead during O(n) linear scans of the memory database.
**Action:** Extract the magnitude calculation of the query vector outside loops using the new `VectorMath.magnitude(_:)` method, and use the optimized `VectorMath.cosineSimilarity(_:magnitudeA:_:)` overload to bypass the redundant magnitude computation.
