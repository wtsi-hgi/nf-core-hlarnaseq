# nf-core/hlarnaseq: Conda environment setup

At this early development stage the pipeline assumes every tool it invokes
is already available in an operator-prepared Conda environment - there is no container packaging yet.
(Except of the tools already available as containers form upstream NF-Core).
Several bundled tools have conflicting or legacy dependencies (Python 2, old R, old kallisto),
so the pipeline is split across **3 separate environments**.
Steps invoke the non-main environments by name via `conda run -n <env>`, so the exact names below matter.

Ready-to-use environment files are provided under [`envs/`](../envs/).
Create each with conda/mamba:

```bash
conda env create -f envs/<name>.yml
# or: mamba env create -f envs/<name>.yml - much faser if you have mamba installed
```

| Environment      | File                                                    | Used by                                                               | Needed for |
| ---------------- | ------------------------------------------------------- | --------------------------------------------------------------------- | ---------- |
| `nf-core`        | [`envs/nf-core.yml`](../envs/nf-core.yml)               | Nextflow itself; `HLA_CONSENSUS`, arcasHLA-combine, HLApm-input steps | Always     |
| `hlapm`          | [`envs/hlapm.yml`](../envs/hlapm.yml)                   | `HLAPM_BUILD_REF`                                                     | Always     |
| `hlapm-quantify` | [`envs/hlapm-quantify.yml`](../envs/hlapm-quantify.yml) | `HLAPM_QUANTIFY_READS`, `HLAPM_SUMMARIZE_READCOUNTS`                  | Always     |

Activate `nf-core` to launch the pipeline itself.

```bash
conda activate nf-core
```

The other 2 are consumed automatically by name and never need manual activation.

## Notes

- None of these 3 environments are created, modified, or provisioned by
  the pipeline itself - all are operator-prepared preconditions, checked
  at runtime by each module (`command -v <tool>` inside `conda run -n
<env>`) and failing fast with a clear error if missing.
- The files under `envs/` were generated from working environments with
  `conda env export --from-history` and hand-trimmed to the packages each
  step actually needs; version floors/pins mirror `docs/usage.md`, which
  remains the source of truth for per-parameter detail.
- `ARCASHLA_VALIDATE_FASTQ`, `ARCASHLA_GENOTYPE`, `HLALA_TYPING`,
  `HIBAG_PREDICT`, and STAR (`STAR_GENOMEGENERATE`/`STAR_ALIGN`) are exceptions
  to the "operator-prepared Conda environment" model above: each comes from its
  own module-owned `conda`/`environment.yml` and `container` directive, resolved
  automatically via `-profile conda`/`singularity`/`docker`, not from any
  environment in the table above. See
  [usage docs](usage.md#rna-samplesheet-input),
  [usage docs](usage.md#arcashla-genotyping-environment),
  [usage docs](usage.md#wgs-samplesheet-input),
  [usage docs](usage.md#hibag-dependency), and
  [usage docs](usage.md#hlapm-star-index) for details.
  `HIBAG_PREDICT` is the most recent to move: `bioconductor-hibag` used to be
  listed in `envs/nf-core.yml` and is no longer, so the SNP-array path now
  needs one of those profiles rather than a package in the `nf-core`
  environment.
  Note that `HLALA_TYPING`'s prepared HLA-LA graph (`--hlala_graph_dir`) is
  still an operator-prepared input, exactly like `ARCASHLA_GENOTYPE`'s
  `--arcashla_reference_dir`; only the tool itself is module-provisioned.
- Both of those operator-prepared reference inputs have a helper script under
  [`scripts/`](../scripts/) that builds them once, out of band, inside the same
  pinned container image the pipeline itself runs. Neither is created by the
  pipeline:
  - `scripts/build_arcashla_reference.sh <dir>` &rarr;
    `--arcashla_reference_dir` (run `scripts/build_image_arcashla.sh` first;
    that image is built locally). See
    [usage docs](usage.md#arcashla-genotyping-environment).
  - `scripts/build_reference_hlala.sh <dir>` &rarr; `--hlala_graph_dir`
    (~2.25 GB download, ~29 GB on disk, a few hours, up to 40 GB of RAM; no
    image-build step needed, the `hla-la:1.0.4` image is public). It fetches
    and indexes a _published_ PRG graph and cannot construct one from scratch.
    See [usage docs](usage.md#preparing-the-hla-la-graph).
  - Both scripts are idempotent and document their override variables under
    `--help`.
