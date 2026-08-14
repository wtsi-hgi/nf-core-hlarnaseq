# nf-core/hlarnaseq: Conda environment setup

At this early development stage the pipeline assumes every tool it invokes
is already available in an operator-prepared Conda environment - there is no container packaging yet.
(Except of the tools already available as containers form upstream NF-Core).
Several bundled tools have conflicting or legacy dependencies (Python 2, old R, old kallisto), 
so the pipeline is split across **5 separate environments**. 
Steps invoke the non-main environments by name via `conda run -n <env>`, so the exact names below matter.

Ready-to-use environment files are provided under [`envs/`](../envs/).
Create each with conda/mamba:

```bash
conda env create -f envs/<name>.yml
# or: mamba env create -f envs/<name>.yml - much faser if you have mamba installed
```

| Environment      | File                                                    | Used by                                                               | Needed for                      |
|------------------|---------------------------------------------------------|-----------------------------------------------------------------------|---------------------------------|
| `nf-core`        | [`envs/nf-core.yml`](../envs/nf-core.yml)               | Nextflow itself; `HLA_CONSENSUS`, arcasHLA-combine, HLApm-input steps | Always                          |
| `arcas-hla`      | [`envs/arcas-hla.yml`](../envs/arcas-hla.yml)           | `ARCASHLA_GENOTYPE`                                                   | Always (RNA input is mandatory) |
| `hla-la`         | [`envs/hla-la.yml`](../envs/hla-la.yml)                 | `HLALA_RUN`                                                           | Only with `--wgs_samples`       |
| `hlapm`          | [`envs/hlapm.yml`](../envs/hlapm.yml)                   | `HLAPM_BUILD_REF`                                                     | Always                          |
| `hlapm-quantify` | [`envs/hlapm-quantify.yml`](../envs/hlapm-quantify.yml) | `HLAPM_QUANTIFY_READS`, `HLAPM_SUMMARIZE_READCOUNTS`                  | Always                          |

Activate `nf-core` to launch the pipeline itself. 

```bash
conda activate nf-core
```

The other 4 are consumed automatically by name and never need manual activation.


## Notes

- None of these 5 environments are created, modified, or provisioned by
  the pipeline itself - all are operator-prepared preconditions, checked
  at runtime by each module (`command -v <tool>` inside `conda run -n
  <env>`) and failing fast with a clear error if missing.
- The files under `envs/` were generated from working environments with
  `conda env export --from-history` and hand-trimmed to the packages each
  step actually needs; version floors/pins mirror `docs/usage.md`, which
  remains the source of truth for per-parameter detail.
- STAR (`STAR_GENOMEGENERATE`/`STAR_ALIGN`) is the one exception to the
  "operator-prepared Conda environment" model: it comes from the
  standard nf-core module's own pinned container/`environment.yml` via
  `-profile singularity`/`docker`/`conda`, not from any environment above.
  See [usage docs](usage.md#hlapm-star-index) for details.
