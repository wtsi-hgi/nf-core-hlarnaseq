# Manual Validation Reference

Use these checks when the change cannot be fully proven by automated tests.

## Pipeline Smoke

- Run `./pipeline_testdata_run.sh` to execute the local testdata through Nextflow; it defaults to `-profile singularity` and clones `HLApm` into the run directory (`RUN_DIR`, default `artifacts/testdata-run`) on first use.
- Override `PROFILE`, `RUN_DIR`, `OUTDIR`, or the other environment variables it lists via `./pipeline_testdata_run.sh --help` as needed, or pass `-profile <profile>` through directly.
- Record the run directory path (default `artifacts/testdata-run/`) in the validation report.
- `nextflow run . -profile test` remains a lighter-weight fallback when the full testdata run isn't needed.
- Container validation (`docker info`, `-profile docker`/`-profile singularity` runs) is permitted and preferred when the runtime is available; record a genuinely unavailable runtime as a blocked check with residual risk, not a policy skip.

## Schema and Samplesheet

- Confirm `nextflow_schema.json` documents every new parameter.
- Confirm `assets/schema_input.json` matches documented samplesheet columns.
- Confirm `docs/usage.md` has a minimal valid example.

## Outputs

- Confirm `docs/output.md` documents every user-facing output directory and file pattern.
- Confirm new outputs are emitted from modules/subworkflows/workflows with stable names.
- Confirm nf-test snapshots are updated only after inspecting output content.

## Dependencies

- Confirm any new tool is expected from the active Conda environment, a container image, or both, and that the module's `environment.yml` matches what's declared.
- Confirm tool versions are captured in pipeline software versions output.
- Confirm `CITATIONS.md` and README citations are updated when new tools or methods are introduced.
