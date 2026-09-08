# arcashla_reference_stub

This directory is a placeholder used solely to satisfy
`--arcashla_reference_dir`'s launch-time checks
(`arcashlaReferenceDirExistsError()`) under `-profile test`.

It is **not** a real or partial arcasHLA reference (IMGT/HLA database +
kallisto index built by `scripts/build_arcashla_reference.sh`), and it
contains no reference data.

`hla.idx` and `hla.p.json` here are **placeholder text files**, not the
binary kallisto index and JSON a real reference has. They exist because
`arcashlaReferenceDirExistsError()` requires both before a non-stub run,
so that an empty or half-built reference directory is rejected at launch
instead of failing much later as an arcasHLA
`FileNotFoundError: .../dat/ref/hla.p.json`. That content check is skipped
for stub runs, but `-profile test` also carries several **non**-stub tests
(the samplesheet/parameter rejection tests, and the `validatefastq`
mismatch test), and those have to get past it to reach the failure they
actually assert. Each file says what it is if opened.

Nothing reads either file. The tests using this directory either run
`-stub-run`, where `ARCASHLA_GENOTYPE`'s `stub:` block never invokes
arcasHLA, or fail earlier than `ARCASHLA_GENOTYPE` - at parameter and
samplesheet validation, or at `ARCASHLA_VALIDATE_FASTQ`.

Do not point `--arcashla_reference_dir` at this directory for a real
pipeline run: the launch checks would pass, and `ARCASHLA_GENOTYPE` would
then fail inside the task, since there is no reference data here. Build a
real one with `scripts/build_arcashla_reference.sh`.
