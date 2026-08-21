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
- Runtime tool dependencies are provided either by the currently active Conda environment 
  or by Docker/Singularity/Apptainer containers, 
  following   the nf-core module convention of pairing each module's `conda`/
  `environment.yml` declaration with a matching `container` directive.
- Follow NF-Core template and guidelines
- Use existing NF-Core modules when possible

Do not introduce alternative frameworks and technologies.
Docker and Singularity/Apptainer container creation and execution are permitted; 
prefer the standard nf-core pattern of deriving both the `conda` and `container` directives 
from one module `environment.yml`.

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
- Keep custom analysis scripts in Python or R under `bin/`, regardless of
  whether a module runs via Conda or a container — `bin/` scripts are staged
  onto `PATH` in both cases.
- Assume that everything required to run the pipeline and custom scripts from
  `bin/` is available either in the currently active Conda environment,
  normally the `nf-core` profile, or in the module's container when running
  a containerized profile;
- Docker, Singularity, and Apptainer container creation, building, pulling,
  and running are permitted. Prefer the standard nf-core module pattern:
  declare dependencies once in a module `environment.yml`, feed it to the
  `conda` directive, and pair it with a matching `container` directive
  (a pinned Biocontainers/Wave image, or a module-local `Dockerfile` when
  the tool is not on Bioconda).
- Every runtime tool dependency should be documented, whether it is expected
  from the active Conda environment, a container image, or both.
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

Container validation is enabled:

- run `docker info` (and `singularity --version` / `apptainer --version` when
  targeting Singularity/Apptainer) to confirm the container runtime is
  available before relying on containerized profiles;
- containerized `nextflow run` profiles (`docker`, `singularity`, `apptainer`)
  may be created and run as part of validation;
- if a container runtime or a specific image is genuinely unavailable
  (missing daemon, no network/registry access), record that explicitly in
  `artifacts/3_validate.md` as a blocked check with residual risk.

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
- `nextflow run . -profile docker,test --outdir <OUTDIR>`
- `nextflow run . -profile singularity,test --outdir <OUTDIR>`
- `pre-commit run --all-files`

If a check is unavailable or blocked by missing tools, network, or test data,
record that explicitly in `artifacts/3_validate.md` with the command attempted
and the residual risk.

Validation scripts should write logs and Nextflow output directories under a
unique `artifacts/validation/<timestamp>/` directory so repeated validation
runs do not overwrite earlier evidence.

## Human-in-the-loop Rules

- Ask clarifying questions only when a reasonable assumption would risk wrong pipeline behavior or wasted implementation.
- Default behavior for every pipeline change is the full plan → approve → implement → validate cycle described above. This is the default for any request to add, fix, change, or refactor pipeline behavior, even if the human does not mention "plan" explicitly.
- For implementation requests without an approved plan, produce the plan first and wait.
- Explicit approval means the human says the current `artifacts/1_plan.md` is approved, for example: "approved", "approve the plan", or "implement this plan".
- `artifacts/2_implement.md` must quote or summarize the approval message with date/time when available.
- Keep each iteration small enough for practical review.
- Never hide skipped validation.
- Do not rewrite unrelated scaffold files merely to satisfy style preferences.

### Bypassing the plan/approve cycle

- The plan → approve → implement → validate cycle may be skipped only when the human explicitly instructs a direct change in the same request, using clear language such as "make this change directly", "skip the plan", "just implement it, no plan needed", or "don't stop for approval". A generic sense of urgency or a short task description is not sufficient — the instruction to bypass must be explicit and about process, not just about scope.
- When bypassing is explicitly requested:
  - still keep the change small and reviewable, and still avoid unrelated refactors or new frameworks;
  - still run validation appropriate to the change and report results (validation itself is not optional, only the pre-implementation plan/approval stop is skipped);
  - still do not commit to Git unless separately asked;
  - state in the response that the plan/approval step was skipped because the human asked for a direct change, so the bypass is visible and auditable.
- If a bypass instruction is ambiguous (e.g., unclear whether it covers approval, validation, or both), ask a single clarifying question rather than assuming the broadest possible skip.
- AI-configuration-only changes (`AGENTS.md`, `.agents/**`, `.claude/**`, `artifacts/ai-*.md`) already skip the pipeline plan/approve/implement/validate cycle by default per "AI Configuration Maintenance" above; that is a separate, standing exception and does not require the human to say anything extra.
