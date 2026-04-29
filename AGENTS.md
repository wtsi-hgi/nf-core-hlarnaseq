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

Preferred checks, when available:

- `nf-core pipelines lint`
- `nf-test test`
- `nextflow run . -profile test,docker --outdir <OUTDIR>`
- `nextflow run . -profile debug,test,docker --outdir <OUTDIR>`
- `pre-commit run --all-files`

If a check is unavailable or blocked by missing tools, network, Docker, or test data, record that explicitly in `artifacts/3_validate.md` with the command attempted and the residual risk.

## Human-in-the-loop Rules

- Ask clarifying questions only when a reasonable assumption would risk wrong pipeline behavior or wasted implementation.
- For implementation requests without an approved plan, produce the plan first and wait.
- Keep each iteration small enough for practical review.
- Never hide skipped validation.
- Do not rewrite unrelated scaffold files merely to satisfy style preferences.
