# Test Data Preparation Scripts

This directory contains local helper scripts for preparing development test data.
The generated files are large and are written below `testdata-make/data/`, which
is not intended to be committed.

## Requirements

Run these scripts from an environment that provides:

- `wget` or `curl`
- `samtools`
- standard POSIX shell utilities

For this early development stage, these tools are expected to come from the
active Conda environment. The scripts do not create or use containers.

## NA12878 HLA-Region WGS Data

Run the steps in order:

```bash
testdata-make/00-download-reference
testdata-make/01-download-na12878-wgs
testdata-make/02-extract-hla-region
```

The scripts are idempotent: if a target file already exists and is non-empty,
the corresponding download or extraction step is skipped.

Outputs:

- `data/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa`
- `data/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa.fai`
- `data/wgs/NA12878.final.cram`
- `data/wgs/NA12878.final.cram.crai`
- `data/hla/NA12878.chr6_hla.GRCh38.bam`
- `data/hla/NA12878.chr6_hla.GRCh38.bam.bai`

By default, the extraction step uses the GRCh38 extended MHC/HLA interval:

```text
chr6:28510120-33480577
```

Override it only when you intentionally need a different region:

```bash
HLA_REGION=chr6:29900000-33100000 testdata-make/02-extract-hla-region
```

The extraction step uses two threads by default. Override with `THREADS`:

```bash
THREADS=8 testdata-make/02-extract-hla-region
```

## Data Sources

Reference genome:

- `http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa`
- `http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa.fai`

NA12878/HG001 WGS CRAM:

- `ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR323/ERR3239334/NA12878.final.cram`
- `ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR323/ERR3239334/NA12878.final.cram.crai`

The full reference and CRAM are large. Make sure there is enough local storage
before running the download steps.

Shared constants and shell helper functions live in `lib/`. The numbered
scripts are the supported entry points.
