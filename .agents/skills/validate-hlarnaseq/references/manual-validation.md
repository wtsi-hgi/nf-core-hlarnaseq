# Manual Validation Reference

Use these checks when the change cannot be fully proven by automated tests.

## Pipeline Smoke

- Run `nextflow run . -profile test --outdir artifacts/validation/nextflow-test`.
- For container validation, run `nextflow run . -profile test,docker --outdir artifacts/validation/nextflow-test-docker` when Docker is available.
- For debug warning checks, run `nextflow run . -profile debug,test,docker --outdir artifacts/validation/nextflow-debug-test-docker` when Docker is available.

## Schema and Samplesheet

- Confirm `nextflow_schema.json` documents every new parameter.
- Confirm `assets/schema_input.json` matches documented samplesheet columns.
- Confirm `docs/usage.md` has a minimal valid example.

## Outputs

- Confirm `docs/output.md` documents every user-facing output directory and file pattern.
- Confirm new outputs are emitted from modules/subworkflows/workflows with stable names.
- Confirm nf-test snapshots are updated only after inspecting output content.

## Dependencies

- Confirm any new tool has a container or Conda declaration compatible with nf-core.
- Confirm tool versions are captured in pipeline software versions output.
- Confirm `CITATIONS.md` and README citations are updated when new tools or methods are introduced.

