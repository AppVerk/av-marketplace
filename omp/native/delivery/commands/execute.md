---
description: "Deliver or resume a plan file: each task goes to the developer agent that owns its files, is reviewed and committed, then the plan's verification and the full code review run. Approved plan-mode plans with ### Task headings start this automatically."
argument-hint: "<plan path>"
---

# Delivery: execute

`read skill://delivery:orchestration` and run its **Delivery run** section with `PLAN_SOURCE` = **$ARGUMENTS** and no `PLAN_FILE`.
