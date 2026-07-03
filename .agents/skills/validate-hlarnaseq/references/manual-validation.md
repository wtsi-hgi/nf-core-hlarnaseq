# Manual Validation Reference

Use these checks when the change cannot be fully proven by automated tests.

## Pipeline Smoke

- Run `./run_tests_remote` to execute `pipeline_testdata_run.sh` on the configured remote VM.
- Use `DRY_RUN=1 ./run_tests_remote` to confirm the sync and remote run paths before executing when needed.
- By default, remote validation downloads only lightweight run evidence and skips `results/` and `nextflow.workdir/`.
- Use `DOWNLOAD_RESULTS=1 ./run_tests_remote` only when result file inspection is necessary.
- Record the downloaded `artifacts/remote-testdata-run/<timestamp>/` path in the validation report.
- Local `nextflow run . -profile test` checks are a fallback only when the user asks for local-only validation or remote access is blocked.
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
