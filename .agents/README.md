# Agent Workflow

This directory contains local Codex skills for developing `nf-core/hlarnaseq`.

The workflow is intentionally human-in-the-loop:

1. Use `plan-pipeline-change` to create a small one-iteration plan in `artifacts/1_plan.md`.
2. The human reviews and approves the plan.
3. Use `implement-nfcore-nextflow` to make the approved changes and write `artifacts/2_implement.md`.
4. Use `validate-hlarnaseq` to run checks, review the diff, and write `artifacts/3_validate.md`.
5. The human reviews the result and commits.

Agents must not commit changes unless explicitly asked.

During the current early-stage development policy, 
assume runtime tools are available in the active Conda environment, 
place custom Python and R scripts under `bin/`, 
and do not create, build, pull, or run containers.

## Roles

- `planner`: uses `plan-pipeline-change`; reads relevant files; writes `artifacts/1_plan.md`; stops for approval.
- `coder`: uses `implement-nfcore-nextflow`; changes only approved scope; writes `artifacts/2_implement.md`.
- `validator`: uses `validate-hlarnaseq`; runs checks and reviews the diff; writes `artifacts/3_validate.md`.
