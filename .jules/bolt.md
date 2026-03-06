## Bolt Journal

## 2024-05-18 - Optimized Cosine Similarity O(N) linear scans
**Learning:** Pre-calculating the query vector's magnitude in an O(N) linear scan avoids recalculating it identically for every DB memory compared. Apple's Accelerate framework vector sums (e.g., `vDSP_svesqD`) are fast, but removing redundant work altogether in the loop speeds up semantic search ranking significantly when the dataset grows.
**Action:** When calculating distances/similarities involving a fixed vector against a large collection, always extract constant magnitude calculations out of the loop and use overloaded optimized comparison functions.
