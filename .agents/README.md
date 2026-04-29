# Agent Workflow

This directory contains local Codex skills for developing `nf-core/hlarnaseq`.

The workflow is intentionally human-in-the-loop:

1. Use `plan-pipeline-change` to create a small one-iteration plan in `artifacts/1_plan.md`.
2. The human reviews and approves the plan.
3. Use `implement-nfcore-nextflow` to make the approved changes and write `artifacts/2_implement.md`.
4. Use `validate-hlarnaseq` to run checks, review the diff, and write `artifacts/3_validate.md`.
5. The human reviews the result and commits.

Agents must not commit changes unless explicitly asked.

