---
name: plan-pipeline-change
description: Create a small, reviewable one-iteration plan for nf-core/hlarnaseq. Use for features, fixes, refactors, module additions, parameter changes, docs updates, or test work. Saves artifacts/1_plan.md and stops for human approval.
---

# Plan Pipeline Change Skill

Use this skill when the user asks to plan any change to `nf-core/hlarnaseq`, or when implementation is requested but no approved plan exists.

## Workflow

1. Read the user request and restate the target behavior.
2. Read `AGENTS.md` and enforce repository constraints.
3. Inspect the relevant pipeline files before planning. Common files include:
   - `main.nf`
   - `workflows/hlarnaseq.nf`
   - `nextflow.config`
   - `nextflow_schema.json`
   - `assets/schema_input.json`
   - `conf/test.config`
   - `tests/default.nf.test`
   - `modules.json`
   - `docs/usage.md`
   - `docs/output.md`
4. Check whether an existing nf-core module or subworkflow should be used before proposing custom process code.
5. If you need to clarify anything, ask questions.
6. Produce a minimal one-iteration plan using `references/plan-template.md`.
7. Save the complete proposed plan to `artifacts/1_plan.md`.
8. Keep scope tight:
   - list in-scope and out-of-scope items;
   - avoid broad rewrites unless explicitly requested;
   - keep the expected review under about 30 minutes.
9. Include coordinated file updates for any changed behavior:
   - parameters: `nextflow.config`, `nextflow_schema.json`, docs, tests;
   - sample sheet columns: `assets/schema_input.json`, docs, tests;
   - outputs: module/workflow emits, `docs/output.md`, nf-test snapshots;
   - tools: module metadata, active-Conda dependency assumptions, `CITATIONS.md`, versions.
10. Include validation commands with pass criteria and note likely blockers.
11. Stop and request human approval. Do not implement.

## Early-Stage Conda Policy

- Treat runtime tools as provided by the currently active Conda environment.
- Plan custom Python and R scripts under `bin/`.
- Do not plan container creation, packaging, pulls, or containerized execution profiles.
- When adding a tool, document the Conda environment expectation, versions reporting, and citation impact instead of adding container packaging.

## Output

Return the completed plan sections in the same order as `references/plan-template.md`.

At the end, add:

`Approval needed: Please confirm this plan is approved. I will not implement until you approve.`

Persist the same content to `artifacts/1_plan.md` before finishing.
