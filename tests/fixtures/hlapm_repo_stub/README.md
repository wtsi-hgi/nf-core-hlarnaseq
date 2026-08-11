# hlapm_repo_stub

This directory is a placeholder used solely to satisfy `--hlapm_repo`'s
directory-existence check (`hlapmRepoExistsError()`) under `-profile test`'s
`-stub-run` smoke test.

It is **not** a real or partial [HLApm](https://github.com/davenportlab/HLApm)
checkout, and it contains no HLApm code or reference data. It is never
actually read: under `-stub-run`, `HLAPM_BUILD_REF`'s `stub:` block never
invokes HLApm or inspects `--hlapm_repo`'s contents.

Do not point `--hlapm_repo` at this directory for a real (non-stub) pipeline
run - `HLAPM_BUILD_REF` would fail against it, since it has no HLApm scripts
or bundled reference data.
