
## 2025-02-17 - Hoisting Invariant Vector Magnitudes in Similarity Loops
**Learning:** The application computes the cosine similarity between a fixed query embedding and many memory vectors. The `VectorMath.cosineSimilarity` function recalculates the magnitude of both vectors on every call. In a loop, recalculating the query vector's magnitude $O(N)$ times is computationally expensive and redundant.
**Action:** When performing vector similarity searches (like `MemoryRepository.searchMemories` or `ContextRanker.rankMemories`), hoist the query vector's magnitude calculation out of the loop using `VectorMath.magnitude` and pass it to an optimized `VectorMath.cosineSimilarity` overload.
