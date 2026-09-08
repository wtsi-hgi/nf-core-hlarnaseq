# arcashla_reference_stub

This directory is a placeholder used solely to satisfy
`--arcashla_reference_dir`'s directory-existence check
(`arcashlaReferenceDirExistsError()`) under `-profile test`'s `-stub-run`
smoke test.

It is **not** a real or partial arcasHLA reference (IMGT/HLA database +
kallisto index built by `scripts/build_arcashla_reference.sh`), and it
contains no reference data. It is never actually read: under `-stub-run`,
`ARCASHLA_GENOTYPE`'s `stub:` block never invokes arcasHLA or inspects
`--arcashla_reference_dir`'s contents.

Do not point `--arcashla_reference_dir` at this directory for a real
(non-stub) pipeline run - `ARCASHLA_GENOTYPE` would fail against it, since
it has no reference data.
