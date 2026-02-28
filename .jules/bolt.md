## 2024-05-24 - Pre-calculate Magnitudes in Linear Search
**Learning:** When performing semantic search over many embeddings without a vector index (e.g. `PersistenceService.searchMemories`), computing the query vector's magnitude inside the similarity loop is highly redundant and noticeably affects performance.
**Action:** Always pre-calculate the query vector's magnitude (L2 norm) *before* the loop, and use an optimized `cosineSimilarity` method that accepts the pre-computed magnitude.
