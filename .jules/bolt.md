## 2024-03-04 - [Cosine Similarity Optimization]
**Learning:** Calculating cosine similarity in a loop (e.g., against all stored memories) recalculates the query vector's magnitude every time. For high-dimensional embeddings, this represents significant redundant work.
**Action:** Hoist the query vector's magnitude calculation outside the loop and use an overloaded `cosineSimilarity` method that accepts the pre-calculated magnitude.
