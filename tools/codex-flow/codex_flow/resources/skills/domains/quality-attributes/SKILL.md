# Quality Attributes

During review, check:
- correctness
- regression risk
- testability
- maintainability
- safety
- security
- observability
- minimality: the mechanism is no larger than the design's declared requirements, and the implementation is no larger than the approved design requires — flag what serves neither

This item's wording is parsed by a test. `tests/verify-config-consistency.sh` in the genai-automations repo requires both scope clauses above ("the mechanism is no larger than ..." and "the implementation is no larger than the approved design requires") to survive; reword freely around them, but run that suite afterwards.

Separate confirmed findings from missing evidence.
Treat missing verification as a review concern.
