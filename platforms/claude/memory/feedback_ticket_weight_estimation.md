---
name: feedback-ticket-weight-estimation
description: "Weight estimates must be stated in the conversation before YAML is written, using explicit arithmetic"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 91c852b3-c48e-4362-9c41-17284cd43801
---

Always produce a visible weight estimate in the conversation before writing ticket YAML. Use this exact format for each issue:

```
Weight estimate — "<issue title>":
  design: Xh  — [what needs to be read/understood/resolved]
  coding:  Yh  — [what gets implemented]
  review:  Zh  — [how it will be tested + review overhead]
  total:   Th  → weight: N
```

The `weight:` in YAML must match the stated value. Do not write YAML until all estimates are stated.

**Why:** Estimation done mentally (without visible output) results in anchoring to intuition or examples rather than arithmetic. The WiFi credentials ticket got weight: 2 (should have been 16–24) because the estimate was never stated — it was filled in implicitly during YAML generation. Making the estimate visible before YAML forces the arithmetic and lets the user catch errors.

**How to apply:** Step 3 of /ticket is now "Estimate Weights" — it must execute and produce output before step 4 "Generate YAML". Device-dependent testing (reboot, flash, sensor) adds an 8h bump before rounding. Reference scale: 8=1 day, 16=2 days, 24=3 days, 32=arch/research ticket. Never below 8.
