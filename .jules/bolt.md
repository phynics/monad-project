## 2024-05-15 - [JSON Parsing Performance]
**Learning:** `JSONDecoder` overhead is severe for high-frequency accessors in `Memory` parsing primitive collections like arrays and dictionaries. `JSONSerialization` is much more efficient for these simple types.
**Action:** Replace `JSONDecoder().decode` with `JSONSerialization.jsonObject` for `tagArray`, `embeddingVector`, and `metadataDict` computed properties to avoid high initialization cost of `JSONDecoder`.
