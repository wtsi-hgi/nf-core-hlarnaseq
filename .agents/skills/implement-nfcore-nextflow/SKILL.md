---
name: implement-nfcore-nextflow
description: Implement an approved one-iteration plan for nf-core/hlarnaseq using Nextflow DSL2, Python, or R as appropriate. Preserves nf-core conventions, updates coordinated schema/docs/tests, and writes artifacts/2_implement.md.
---

# Implement nf-core Nextflow Skill

Use this skill only after a human has explicitly approved `artifacts/1_plan.md`.

## Workflow

1. Confirm approval.
   - Locate `artifacts/1_plan.md`.
   - If approval is not explicit, stop and request approval before changing code.
2. Re-read `AGENTS.md`.
3. Implement only the approved scope.
4. Follow nf-core conventions:
   - use Nextflow DSL2;
   - prefer existing nf-core modules/subworkflows;
   - keep custom local modules small when needed;
   - use topic `versions` or standard versions channels where relevant;
   - ensure all runtime dependencies are available in containers or Conda;
   - maintain nf-schema parameter validation.
5. Update coordinated files when behavior changes:
   - parameters: `nextflow.config`, `nextflow_schema.json`, docs, tests;
   - sample sheet: `assets/schema_input.json`, docs, tests;
   - outputs: workflow/module emits, `docs/output.md`, nf-test snapshots;
   - tools: module metadata, containers/Conda, versions, `CITATIONS.md`;
   - user-facing changes: `README.md`, `CHANGELOG.md` when appropriate.
6. Keep the diff small and reviewable. Do not perform unrelated template cleanup.
7. Run focused checks from the plan when feasible.
8. Save implementation notes to `artifacts/2_implement.md`.
9. Include:
   - approved plan reference;
   - what changed and why;
   - files changed;
   - validation attempted and results;
   - blocked checks and residual risks;
   - any follow-up work intentionally deferred.

## Guardrails

- Do not commit changes.
- Do not modify generated snapshots blindly; only update snapshots when behavior is understood.
- Do not introduce new frameworks or non-containerized runtime assumptions.
- Do not replace nf-core scaffold patterns with custom conventions.
- If implementation reveals that the approved plan is materially wrong, stop and ask for a revised plan.

