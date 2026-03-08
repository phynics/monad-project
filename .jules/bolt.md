
## 2025-03-08 - [Optimize Cosine Similarity in Loops]
**Learning:** In linear scan search algorithms matching memory vectors (like `PersistenceService.searchMemories` and `ContextRanker.rankMemories`), the query vector's magnitude was repeatedly calculated on every iteration via Accelerate's `vDSP_svesqD`.
**Action:** Extract the magnitude calculation of the stationary query vector outside the loop, creating an optimized overload of `cosineSimilarity` to halve the overall `vDSP_svesqD` operations per search query.
