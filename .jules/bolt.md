## 2024-06-25 - Avoid Redundant Vector Magnitude Calculations
**Learning:** In loops comparing a constant query vector against multiple target vectors (e.g., semantic search or context ranking), re-calculating the magnitude of the query vector for every comparison using Accelerate's `vDSP_svesqD` is O(N) redundant work.
**Action:** Always pre-calculate the magnitude of the constant vector outside the loop and use an optimized similarity function that accepts the pre-calculated magnitude.
