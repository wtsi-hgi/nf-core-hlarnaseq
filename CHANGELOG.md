# nf-core/hlarnaseq: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of nf-core/hlarnaseq, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Added required `--rna_samples` and `--hla_region` inputs and extraction of arcasHLA-ready paired MHC FASTQs with samtools.
- Added per-sample validatefastq pairing validation for extracted arcasHLA reads, with validation logs under `arcashla/validation/`.
- Added an `ARCASHLA_GENOTYPE` step that runs `arcasHLA genotype` on validated RNA reads (configurable via `--arcashla_genes`), writing per-sample results under `arcashla/genotype/`. Genotyping runs inside a dedicated, operator-prepared `arcas-hla` Conda environment.
- Added an `ARCASHLA_COMBINE` step that merges per-sample arcasHLA genotype JSON results into a single long-format `arcashla/arcasHLA_combined.csv`, using a new `bin/combine_arcashla_genotypes.R` script.
- Added a standalone `bin/call_hla_consensus.py` script (argparse CLI) that calls a consensus HLA allele per WGS individual by combining `ARCASHLA_COMBINE` RNA genotypes with `HLALA_COMBINE` WGS genotypes via an RNA/WGS sample key. Not yet wired into the Nextflow workflow.

### `Changed`

- Changed `HLALA_COMBINE` to emit tab-separated `hlala/HLA-LA_combined.tsv` (was comma-separated `HLA-LA_combined.csv`), adding a `Locus` column alongside `sample_id` and `HLA_allele`.

### `Fixed`

- Fixed `bin/combine_arcashla_genotypes.R` returning an under-shaped, sample-ID-less row for samples whose arcasHLA genotype JSON is the valid-but-empty `{}` (not enough reads to genotype), so the combined CSV now correctly NA-pads alleles while preserving `rna_sample_id` for that sample.

### `Dependencies`

### `Deprecated`

- Removed the generic `--input` FASTQ samplesheet contract in favor of the RNA-specific manifest.
