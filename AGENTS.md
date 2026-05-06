# HlaRNASeq AI-Agent Instructions

This file is the single source of truth for how agents must work in this repository.

## Project Overview

You are helping develop
**nf-core/hlarnaseq** -- a bioinformatics pipeline that
precisely quantifies human HLA gene expression from RNA-seq data
by using personalized reference genomes.

## Technology Stack (fixed)
- Nextflow for workflow execution
- Python and R for data analysis
- All external utilities must be available in containers
- Follow NF-Core template and guidelines
- Use existing NF-Core modules when possible

Do not introduce alternative frameworks and technologies.

## Development Model

Work one small, reviewable iteration at a time.

1. Plan the change and save the proposed plan to `artifacts/1_plan.md`.
2. Stop for human approval before implementation.
3. After approval, implement only the approved scope.
4. Save implementation notes to `artifacts/2_implement.md`.
5. Validate the change and save results to `artifacts/3_validate.md`.
6. Stop for human review. The human reviews and commits.

Do not commit changes to Git.

If `artifacts/` does not exist, AI agents must create it before writing
required reports or validation outputs.

## AI Configuration Maintenance

Changes limited to `AGENTS.md`, `.agents/**`, or `artifacts/ai-*.md`
may be handled as AI-configuration maintenance rather than pipeline
implementation.

For AI-configuration maintenance:

- do not change pipeline behavior;
- preserve the no-commit rule;
- write review or change notes to an `artifacts/ai-*.md` file when useful;
- use the full plan, approval, implementation, and validation cycle when the
  change affects pipeline code, tests, runtime behavior, parameters, outputs,
  dependencies, or user-facing pipeline docs.

## Repository Conventions

- Preserve nf-core template structure and naming conventions.
- Prefer nf-core/modules and nf-core/subworkflows over local custom code when a suitable maintained component exists.
- Keep workflow logic in Nextflow DSL2.
- Keep helper analysis scripts in Python or R only when they are genuinely needed.
- Every runtime dependency must be declared through nf-core-compatible process metadata, containers, Conda environments, or module definitions.
- Keep containerized execution as the default assumption for validation examples.
- Keep test data small and suitable for nf-core test profiles.
- Update `nextflow_schema.json`, docs, tests, and pipeline metadata together when parameters, inputs, or outputs change.
- Preserve parameter validation through nf-schema.

## Pipeline Quality Bar

For pipeline behavior changes, agents must consider:

- channel contracts between workflows, subworkflows, and modules;
- sample sheet schema and validation;
- test profile behavior;
- nf-test coverage or snapshot updates;
- `docs/usage.md`, `docs/output.md`, `README.md`, `CHANGELOG.md`, and citations when user-facing behavior changes;
- whether a matching nf-core module already exists;
- reproducibility of tool versions and containers.

## Validation Expectations

Use the smallest validation set that proves the iteration.

Before running validation, agents must verify that the nf-core Conda
environment is active:

- run `command -v nf-core`, `command -v nf-test`, and `command -v nextflow`;
- if any of these commands are unavailable, activate the environment with
  `conda activate nf-core` when possible;
- if Conda shell activation is unavailable in the agent shell, preserve the
  environment explicitly when running validation, for example:
  `/bin/zsh -lc 'export PATH="/Users/gz3/apps/miniforge/envs/nf-core/bin:$PATH"; .agents/skills/validate-hlarnaseq/scripts/validate.sh'`;
- if the tools are still unavailable, stop and ask the user to activate or fix
  the nf-core environment.

Agents must check that the Docker daemon is reachable before validation:

- run `docker info`;
- if Docker is installed but the daemon is not reachable, stop and ask the user
  to start Docker before running full validation;
- only continue without Docker when the user explicitly requests non-Docker
  validation, and record the skipped Docker checks in `artifacts/3_validate.md`.

When the validation script needs network access, Docker access, or access to
tool caches outside the sandbox, agents must run it with escalated privileges.
In Codex this means calling the shell command with
`sandbox_permissions="require_escalated"` and a justification such as:

> Do you want to allow validation to access network, Docker, and local tool
> caches while preserving the activated nf-core Conda environment?

When escalation is required and the nf-core environment path must be preserved,
use this command shape:

```bash
/bin/zsh -lc 'export PATH="/Users/gz3/apps/miniforge/envs/nf-core/bin:$PATH"; .agents/skills/validate-hlarnaseq/scripts/validate.sh'
```

Preferred checks, when available:

- `nf-core pipelines lint`
- `nf-test test`
- `nextflow run . -profile test,docker --outdir <OUTDIR>`
- `nextflow run . -profile debug,test,docker --outdir <OUTDIR>`
- `pre-commit run --all-files`

If a check is unavailable or blocked by missing tools, network, Docker, or test data, record that explicitly in `artifacts/3_validate.md` with the command attempted and the residual risk.

Validation scripts should write logs and Nextflow output directories under a
unique `artifacts/validation/<timestamp>/` directory so repeated validation
runs do not overwrite earlier evidence.

## Human-in-the-loop Rules

- Ask clarifying questions only when a reasonable assumption would risk wrong pipeline behavior or wasted implementation.
- For implementation requests without an approved plan, produce the plan first and wait.
- Explicit approval means the human says the current `artifacts/1_plan.md` is approved, for example: "approved", "approve the plan", or "implement this plan".
- `artifacts/2_implement.md` must quote or summarize the approval message with date/time when available.
- Keep each iteration small enough for practical review.
- Never hide skipped validation.
- Do not rewrite unrelated scaffold files merely to satisfy style preferences.
