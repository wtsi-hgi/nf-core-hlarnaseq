---
name: plan-pipeline-change
description: Create a small, reviewable one-iteration plan for nf-core/hlarnaseq. Use for features, fixes, refactors, module additions, parameter changes, docs updates, or test work. Saves artifacts/1_plan.md and stops for human approval.
---

# Plan Pipeline Change Skill

Use this skill when the user asks to plan any change to `nf-core/hlarnaseq`, or when implementation is requested but no approved plan exists. This is the default for any pipeline change request, whether or not the user says the word "plan".

Skip this skill only when the user explicitly asks to bypass the plan/approval step for this change (e.g. "make this change directly", "skip the plan", "no plan needed"). In that case go straight to `implement-nfcore-nextflow`, but still keep the change small, still validate afterward, still don't commit, and say plainly that the plan step was skipped because the human asked for a direct change. See `AGENTS.md` § "Bypassing the plan/approve cycle" for the exact bar for what counts as explicit.

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

## Dependency and Container Policy

- Treat runtime tools as provided by the currently active Conda environment,
  or by a Docker/Singularity/Apptainer container built from the module's
  `environment.yml` — both are permitted.
- Plan custom Python and R scripts under `bin/`.
- Container creation, packaging, pulls, and containerized execution profiles
  may be planned. Prefer the standard nf-core pattern: one module
  `environment.yml` feeding both the `conda` directive and a matching
  `container` directive.
- When adding a tool, document the Conda environment expectation (and/or
  container image), versions reporting, and citation impact.

## Output

Return the completed plan sections in the same order as `references/plan-template.md`.

At the end, add:

`Approval needed: Please confirm this plan is approved. I will not implement until you approve.`

Persist the same content to `artifacts/1_plan.md` before finishing.
