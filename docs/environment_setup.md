# nf-core/hlarnaseq: Conda environment setup

**No pipeline step depends on an operator-prepared Conda environment any more.**
Every module now declares its own dependencies and gets them from Nextflow under
`-profile conda`, `docker`, `singularity` or `apptainer`. Only one
operator-prepared environment remains, and it exists solely to _launch_ the
pipeline:

| Environment | File                                      | Used by                                                    | Needed for |
| ----------- | ----------------------------------------- | ---------------------------------------------------------- | ---------- |
| `nf-core`   | [`envs/nf-core.yml`](../envs/nf-core.yml) | Nextflow, nf-core and nf-test themselves; `testdata-make/` | Always     |

Create it with conda/mamba and activate it to launch the pipeline:

```bash
conda env create -f envs/nf-core.yml
# or: mamba env create -f envs/nf-core.yml - much faster if you have mamba installed
conda activate nf-core
```

No `conda run -n <env>` call sites are left in the pipeline, so no environment
name matters at runtime any more.

## Notes

- `envs/nf-core.yml` is not created, modified, or provisioned by the pipeline
  itself - it is an operator-prepared precondition, and the only one.
  It deliberately no longer carries the Python/R interpreters and libraries the
  `bin/` analysis scripts need: those come from
  [`containers/datatools/environment.yml`](../containers/datatools/environment.yml)
  (see below). `samtools` is retained only because the `testdata-make/`
  fixture-building scripts invoke it directly; no pipeline step needs it here.
- `envs/nf-core.yml` was generated from a working environment with
  `conda env export --from-history` and hand-trimmed; `docs/usage.md` remains
  the source of truth for per-parameter detail.
- **Every module is provisioned from its own `conda`/`environment.yml` plus a
  matching `container` directive**, resolved automatically via
  `-profile conda`/`docker`/`singularity`/`apptainer`. Running the pipeline with
  none of those profiles now leaves these steps unprovisioned, and each fails
  fast with a message naming the profiles rather than silently using whatever is
  on the host `PATH`. See
  [usage docs](usage.md#rna-samplesheet-input),
  [usage docs](usage.md#arcashla-genotyping-environment),
  [usage docs](usage.md#wgs-samplesheet-input),
  [usage docs](usage.md#hibag-dependency),
  [usage docs](usage.md#hlapm-container),
  [usage docs](usage.md#hlapm-read-quantification-container),
  [usage docs](usage.md#shared-data-tools-container), and
  [usage docs](usage.md#hlapm-star-index) for details.
- Most modules own their environment file. Four share one, because they run this
  repository's own small `bin/` analysis scripts over the same two interpreters
  rather than a bioinformatics tool of their own: `HLA_CONSENSUS`,
  `HLAPM_PREPARE_INPUT`, `ARCASHLA_COMBINE` and `HLAPM_SUMMARIZE_READCOUNTS` all
  point at [`containers/datatools/environment.yml`](../containers/datatools/environment.yml)
  (python3 + pandas, R + jsonlite/dplyr/tibble/stringr/purrr/tidyr). See
  [`containers/datatools/README.md`](../containers/datatools/README.md) for why
  that one is shared and how to extend it.
- `HLAPM_QUANTIFY_READS` and `HLAPM_SUMMARIZE_READCOUNTS` were the most recent to
  move, and between them retired the `hlapm-quantify` environment this table used
  to list. It held two unrelated halves: a legacy Python 2 stack, now
  `modules/local/hlapm/quantify_reads/environment.yml` and its own image
  (`scripts/build_image_hlapm_quantify.sh`), and an R stack, now part of the
  shared data-tools image above. `HLA_CONSENSUS`, `HLAPM_PREPARE_INPUT` and
  `ARCASHLA_COMBINE` moved at the same time, off the `nf-core` environment's
  Python/R packages, which is why that file is now launcher-only.
- `HLAPM_BUILD_REF` moved just before them, retiring the `hlapm` environment.
  Its R dependencies come from `modules/local/hlapm/build_ref/environment.yml`.
  It is a partial exception in one respect - HLApm itself is an unpackaged git
  repository, so Conda cannot install it. The module's container image bakes it
  in at a pinned commit (`scripts/build_image_hlapm.sh`), and running under
  `-profile conda` or with no profile still requires an operator-prepared
  checkout passed with `--hlapm_repo`, which is otherwise an optional override.
- `ARCASHLA_EXTRACT` moved before that, and was the last module in the
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
    Indexing means both `HLA-LA --action prepareGraph` and `bwa index` over the
    graph's `extendedReferenceGenome.fa` - the latter because HLA-LA would
    otherwise build it inside every concurrent `HLALA_TYPING` task, all writing
    to the same shared files. See
    [usage docs](usage.md#preparing-the-hla-la-graph).
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
  - `scripts/build_image_hlapm_quantify.sh` &rarr; `HLAPM_QUANTIFY_READS`
    (`quay.io/hlarnaseq/hlapm-quantify-reads:py2.7.15`; the legacy Python 2.7
    stack, with `pybam` pinned by commit. Needs network access to PyPI and
    `github.com` at build time). See
    [usage docs](usage.md#hlapm-read-quantification-container).
  - `scripts/build_image_datatools.sh` &rarr; the four `bin/`-script modules
    (`quay.io/hlarnaseq/datatools:1.0`; shared python3 + R stack). See
    [usage docs](usage.md#shared-data-tools-container) and
    [`containers/datatools/README.md`](../containers/datatools/README.md).
  - All four image scripts document their override variables under `--help`.
    A fully containerized run needs all four built once.
