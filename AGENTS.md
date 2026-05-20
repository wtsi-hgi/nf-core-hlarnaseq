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
- Early-stage development assumption: all external utilities are available in
  the currently active Conda environment
- Follow NF-Core template and guidelines
- Use existing NF-Core modules when possible

Do not introduce alternative frameworks and technologies.
For this development stage, do not create containers, add container packaging, or run containerized
execution profiles.

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
- Keep custom analysis scripts in Python or R under `bin/`.
- For this development srate, place all custom Python and R scripts in `bin/`
  instead of packaging them into containers.
- Assume that everything required to run the pipeline and custom scripts from
  `bin/` is available in the currently active Conda environment, normally the
  `nf-core` profile;
  if shell activation is unavailable, preserve the environment explicitly, for example:
  `/bin/zsh -lc 'export PATH="/Users/gz3/apps/miniforge/envs/nf-core/bin:$PATH"; python bin/<script>.py'`.
- Do not create, build, pull, or run containers for this pipeline at the
  current development stage.
- Every runtime tool dependency should be expected from the active Conda
  environment; document dependency assumptions, but do not add container
  packaging in this stage.
- If some tool or library is missing, stop and ask the developer to install it.
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
- reproducibility of tool versions in the active Conda environment.

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

Container validation is disabled for the current early-stage development policy:

- do not run `docker info`;
- do not create or run containers;
- record in `artifacts/3_validate.md` that containerized validation is
  intentionally out of scope for the current early-stage development policy.

When the validation script needs network access or access to tool caches outside
the sandbox, agents must run it with escalated privileges.
In Codex this means calling the shell command with
`sandbox_permissions="require_escalated"` and a justification such as:

> Do you want to allow validation to access network and local tool caches while
> preserving the activated nf-core Conda environment?

When escalation is required and the nf-core environment path must be preserved,
use this command shape:

```bash
/bin/zsh -lc 'export PATH="/Users/gz3/apps/miniforge/envs/nf-core/bin:$PATH"; .agents/skills/validate-hlarnaseq/scripts/validate.sh'
```

Preferred checks, when available:

- `nf-core pipelines lint`
- `nf-test test`
- `nextflow run . -profile test --outdir <OUTDIR>`
- `nextflow run . -profile debug,test --outdir <OUTDIR>`
- `pre-commit run --all-files`

If a check is unavailable or blocked by missing tools, network, or test data,
record that explicitly in `artifacts/3_validate.md` with the command attempted
and the residual risk. 
Record skipped container checks as intentional policy skips, not environmental failures.

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
