---
name: validate-hlarnaseq
description: Validate nf-core/hlarnaseq changes by running available nf-core, nf-test, Nextflow, and pre-commit checks; review plan compliance; and write artifacts/3_validate.md with findings and residual risks.
---

# Validate HLARNASeq Skill

Use this skill when asked to validate, review, or quality-check an implementation.

## Workflow

1. Read `AGENTS.md`.
2. Read `artifacts/1_plan.md` and `artifacts/2_implement.md` when present.
3. Run `.agents/skills/validate-hlarnaseq/scripts/validate.sh` unless the user requests narrower validation.
4. Review changed files against the approved plan.
5. Check for nf-core pipeline risks:
   - invalid channel contracts;
   - missing `emit` outputs;
   - missing or inconsistent versions reporting;
   - unvalidated parameters;
   - sample sheet schema/docs drift;
   - missing docs for new outputs;
   - missing tool citations;
   - container/Conda dependency gaps;
   - tests or snapshots that do not cover new behavior.
6. Save the validation report to `artifacts/3_validate.md`.
7. Report findings first, ordered by severity, with file and line references.
8. If no findings are found, state that explicitly and list residual risks.

## Required Report Sections

- Status summary
- Checks run
- Blocked checks
- Findings
- Plan compliance
- Residual risks
- Recommended next step

## Severity Guidance

- High: likely runtime failure, incorrect scientific result, invalid schema, broken test profile, missing required containerized dependency.
- Medium: user-facing docs/schema drift, incomplete validation of changed workflow behavior, missing citations or versions for new tools.
- Low: maintainability issues, narrow docs gaps, minor style issues that do not affect execution.

