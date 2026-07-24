# nf-core/hlarnaseq: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of nf-core/hlarnaseq, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Added required `--rna_samples` and `--hla_region` inputs and extraction of arcasHLA-ready paired MHC FASTQs with samtools.
- Added per-sample validatefastq pairing validation for extracted arcasHLA reads, with validation logs under `arcashla/validation/`.

### `Fixed`

### `Dependencies`

### `Deprecated`

- Removed the generic `--input` FASTQ samplesheet contract in favor of the RNA-specific manifest.
