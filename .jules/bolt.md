## 2025-02-19 - [Hoisting Loop-Invariant Vector Math]
**Learning:** In highly mathematical loops (like semantic similarity checks in RAG arrays), recalculating properties like Euclidean norm for the query embedding on every iteration introduces significant, completely redundant CPU overhead (specifically repeating `vDSP_svesqD`).
**Action:** When calculating similarity between a single query and `N` targets, calculate the query's magnitude *once* outside the loop, and use an overloaded `cosineSimilarity` that takes the pre-calculated magnitude as an argument to bypass the calculation.
