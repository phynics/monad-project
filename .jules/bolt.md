## 2026-03-10 - [Pre-calculating Vector Magnitudes in Cosine Similarity Loops]
**Learning:** Calling `vDSP_svesqD` inside a loop for vector comparisons dynamically recalculates the magnitude of the query vector every iteration, resulting in unnecessary overhead, especially for linear search over thousands of memory embeddings.
**Action:** Always decouple invariant vector magnitude calculations in high-frequency semantic matching loops by introducing an overloaded function (`cosineSimilarity(_:_:magnitudeA:)`) and pre-calculating the fixed vectors magnitude prior to iteration.
