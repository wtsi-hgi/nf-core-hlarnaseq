# Manual Validation Reference

Use these checks when the change cannot be fully proven by automated tests.

## Pipeline Smoke

- Run `nextflow run . -profile test --outdir artifacts/validation/nextflow-test`.
- Run `nextflow run . -profile debug,test --outdir artifacts/validation/nextflow-debug-test`.
- Do not run container validation during the current early-stage development policy; record container checks as intentional policy skips.

## Schema and Samplesheet

- Confirm `nextflow_schema.json` documents every new parameter.
- Confirm `assets/schema_input.json` matches documented samplesheet columns.
- Confirm `docs/usage.md` has a minimal valid example.

## Outputs

- Confirm `docs/output.md` documents every user-facing output directory and file pattern.
- Confirm new outputs are emitted from modules/subworkflows/workflows with stable names.
- Confirm nf-test snapshots are updated only after inspecting output content.

## Dependencies

- Confirm any new tool is expected from the active Conda environment during the current early-stage development policy.
- Confirm tool versions are captured in pipeline software versions output.
- Confirm `CITATIONS.md` and README citations are updated when new tools or methods are introduced.
