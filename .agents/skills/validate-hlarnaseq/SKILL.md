---
name: validate-hlarnaseq
description: Validate nf-core/hlarnaseq changes by running available nf-core, nf-test, Nextflow, and pre-commit checks; review plan compliance; and write artifacts/3_validate.md with findings and residual risks.
---

# Validate HLARNASeq Skill

Use this skill when asked to validate, review, or quality-check an implementation.

## Workflow

1. Read `AGENTS.md`.
2. Read `artifacts/1_plan.md` and `artifacts/2_implement.md` when present.
3. Create `artifacts/` if it does not exist.
4. Run `.agents/skills/validate-hlarnaseq/scripts/validate.sh` unless the user requests narrower validation.
5. Review changed files against the approved plan.
6. Check for nf-core pipeline risks:
   - invalid channel contracts;
   - missing `emit` outputs;
   - missing or inconsistent versions reporting;
   - unvalidated parameters;
   - sample sheet schema/docs drift;
   - missing docs for new outputs;
   - missing tool citations;
   - active-Conda dependency gaps;
   - tests or snapshots that do not cover new behavior.
7. Save the validation report to `artifacts/3_validate.md`.
8. Report findings first, ordered by severity, with file and line references.
9. If no findings are found, state that explicitly and list residual risks.

## Required Report Sections

- Status summary
- Checks run
- Blocked checks
- Findings
- Plan compliance
- Residual risks
- Recommended next step

## Severity Guidance

- High: likely runtime failure, incorrect scientific result, invalid schema, broken test profile, missing required active-Conda dependency.
- Medium: user-facing docs/schema drift, incomplete validation of changed workflow behavior, missing citations or versions for new tools.
- Low: maintainability issues, narrow docs gaps, minor style issues that do not affect execution.

## Early-Stage Conda Policy

- Before validation, verify `nf-core`, `nf-test`, and `nextflow` are available from the active environment.
- If they are unavailable, try preserving the expected environment path with `/bin/zsh -lc 'export PATH="/Users/gz3/apps/miniforge/envs/nf-core/bin:$PATH"; ...'`.
- Do not run `docker info` or any containerized profile.
- Record skipped container checks as intentional policy skips, not environmental failures.
