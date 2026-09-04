# nf-core/hlarnaseq: Conda environment setup

At this early development stage the pipeline assumes every tool it invokes
is already available in an operator-prepared Conda environment - there is no container packaging yet.
(Except of the tools already available as containers form upstream NF-Core).
Several bundled tools have conflicting or legacy dependencies (Python 2, old R, old kallisto),
so the pipeline is split across **2 separate environments**.
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
| `hlapm-quantify` | [`envs/hlapm-quantify.yml`](../envs/hlapm-quantify.yml) | `HLAPM_QUANTIFY_READS`, `HLAPM_SUMMARIZE_READCOUNTS`                  | Always     |

Activate `nf-core` to launch the pipeline itself.

```bash
conda activate nf-core
```

The other one is consumed automatically by name and never needs manual activation.

## Notes

- Neither of these environments is created, modified, or provisioned by
  the pipeline itself - all are operator-prepared preconditions, checked
  at runtime by each module (`command -v <tool>` inside `conda run -n
<env>`) and failing fast with a clear error if missing.
- The files under `envs/` were generated from working environments with
  `conda env export --from-history` and hand-trimmed to the packages each
  step actually needs; version floors/pins mirror `docs/usage.md`, which
  remains the source of truth for per-parameter detail.
- `ARCASHLA_EXTRACT`, `ARCASHLA_VALIDATE_FASTQ`, `ARCASHLA_GENOTYPE`,
  `HLALA_TYPING`, `HIBAG_PREDICT`, `HLAPM_BUILD_REF`, and STAR
  (`STAR_GENOMEGENERATE`/`STAR_ALIGN`) are exceptions to the
  "operator-prepared Conda environment" model above: each comes from its
  own module-owned `conda`/`environment.yml` and `container` directive, resolved
  automatically via `-profile conda`/`singularity`/`docker`, not from any
  environment in the table above. See
  [usage docs](usage.md#rna-samplesheet-input),
  [usage docs](usage.md#arcashla-genotyping-environment),
  [usage docs](usage.md#wgs-samplesheet-input),
  [usage docs](usage.md#hibag-dependency),
  [usage docs](usage.md#hlapm-container), and
  [usage docs](usage.md#hlapm-star-index) for details.
  `HLAPM_BUILD_REF` is the most recent to move, and retired the `hlapm`
  environment this table used to list: its R dependencies now come from
  `modules/local/hlapm/build_ref/environment.yml`. It is a partial exception
  in one respect - HLApm itself is an unpackaged git repository, so Conda
  cannot install it. The module's container image bakes it in at a pinned
  commit (`scripts/build_image_hlapm.sh`), and running under `-profile conda`
  or with no profile still requires an operator-prepared checkout passed with
  `--hlapm_repo`, which is otherwise an optional override.
  `ARCASHLA_EXTRACT` moved just before it, and was the last module in the
  pipeline calling a tool off the host `PATH` with no directives of its own: it
  now provisions `samtools` from its own `environment.yml`/`container`
  (`bioconda::samtools=1.24`, the same pin and image the vendored nf-core
  `SAMTOOLS_SORT` module uses, so the two cannot drift apart). `samtools`
  remains listed in `envs/nf-core.yml`, but only because the `testdata-make/`
  fixture-building scripts call it directly - no pipeline step needs it there
  any more.
  `HIBAG_PREDICT` moved just before it: `bioconductor-hibag` used to be
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
    `--arcashla_reference_dir` (~15 GB of scratch on `<dir>`'s own filesystem
    under Singularity/Apptainer, plus network access to `github.com`; run
    `scripts/build_image_arcashla.sh` first, that image is built locally). See
    [usage docs](usage.md#arcashla-genotyping-environment).
  - `scripts/build_reference_hlala.sh <dir>` &rarr; `--hlala_graph_dir`
    (~2.25 GB download, ~29 GB on disk, a few hours, up to 40 GB of RAM; no
    image-build step needed, the `hla-la:1.0.4` image is public). It fetches
    and indexes a _published_ PRG graph and cannot construct one from scratch.
    See [usage docs](usage.md#preparing-the-hla-la-graph).
  - Both scripts are idempotent and document their override variables under
    `--help`.
- Locally built container images have their own helper scripts, which build
  a Docker image and (when `singularity`/`apptainer` is present) convert it to
  a local `.sif` the module's `container` directive references by path. Run the
  one for whichever module you need before using a container profile:
  - `scripts/build_image_arcashla.sh` &rarr; `ARCASHLA_GENOTYPE`
    (`quay.io/hlarnaseq/arcashla-genotype:0.6.0`; no reference baked in).
  - `scripts/build_image_hlapm.sh` &rarr; `HLAPM_BUILD_REF`
    (`quay.io/hlarnaseq/hlapm-build-ref:38faa60`; HLApm itself **is** baked in,
    at a pinned commit, since it has no Conda package. Needs network access to
    `github.com` at build time). See [usage docs](usage.md#hlapm-container).
