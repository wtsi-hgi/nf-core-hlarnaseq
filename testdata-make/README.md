# Test Data Preparation Scripts

This directory contains local helper scripts for preparing development test
data. The generated files are large and are written below `testdata-make/data/`,
which is not intended to be committed.

The final compact bundle for hlarnaseq defaults to:

```text
testdata-make/data/hlarnases-testdata/
  reference/
  rnaseq/
    gene_counts/
    hla_bam/
    unmapped_fastq/
  wgs/
```

The other directories below `testdata-make/data/` are intermediate download,
reference, and nf-core/rnaseq work/output directories.

## Requirements

Run these scripts from an environment that provides:

- `wget` or `curl`
- `gzip`
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

- `data/hlarnases-testdata/reference/GRCh38.primary_assembly.genome.fa.gz`
- `data/hlarnases-testdata/reference/GRCh38.primary_assembly.genome.fa`
- `data/hlarnases-testdata/reference/GRCh38.primary_assembly.genome.fa.fai`
- `data/hlarnases-testdata/reference/gencode.v<release>.primary_assembly.annotation.gtf.gz`
- `data/wgs/NA12878.final.cram`
- `data/wgs/NA12878.final.cram.crai`
- `data/hlarnases-testdata/wgs/NA12878.chr6_hla.GRCh38.bam`
- `data/hlarnases-testdata/wgs/NA12878.chr6_hla.GRCh38.bam.bai`

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

Reference genome and annotation:

- `https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_<release>/GRCh38.primary_assembly.genome.fa.gz`
- `https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_<release>/gencode.v<release>.primary_assembly.annotation.gtf.gz`

By default, `00-download-reference` uses GENCODE human release 50. Override
with `GENCODE_RELEASE=<release>` when a fixed or newer GENCODE release is
needed. The script decompresses and indexes the primary assembly genome FASTA
with `samtools faidx`, then checks that exon records in the GTF contain
`gene_id` attributes.

NA12878/HG001 WGS CRAM:

- `ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR323/ERR3239334/NA12878.final.cram`
- `ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR323/ERR3239334/NA12878.final.cram.crai`

The full reference and CRAM are large. Make sure there is enough local storage
before running the download steps.

Shared constants and shell helper functions live in `lib/`. The numbered
scripts are the supported entry points.

## GM12878 RNA Data for hlarnaseq Inputs

Download and convert the GM12878 / NA12878-compatible RNA-seq FASTQs:

```bash
testdata-make/05-download-na12878-rna
```

By default this writes the SRA cache, FASTQs, logs, and RNA download manifest
under `testdata-make/data/gm12878_rnaseq_fastq/`.

Then prepare an nf-core/rnaseq samplesheet from the downloaded paired FASTQs:

```bash
testdata-make/06-make-rnaseq-samplesheet
```

Run the RNA samples through nf-core/rnaseq with STAR alignment, STAR two-pass
mode, saved unaligned reads, and pseudoalignment disabled:

```bash
testdata-make/07-run-rnaseq-star-featurecounts
```

The default static nf-core/rnaseq parameters are in
`testdata-make/rnaseq.params.json`. They include STAR alignment, saved
unaligned reads, disabled pseudoalignment, and `featurecounts_group_type=gene_id`
for compatibility with GENCODE GTF exon attributes. Override the params file
with `RNASEQ_PARAMS_FILE=/path/to/params.json` if needed.

The default Nextflow resource config is in
`testdata-make/rnaseq.nextflow.config`. It caps process CPU requests at 8 for
the VM and process memory requests at 48 GB. It explicitly caps
`MAKE_TRANSCRIPTS_FASTA`, which otherwise asks RSEM for 12 threads and 72 GB.
Override with `--rnaseq_max_cpus <N>` or `--rnaseq_max_memory '<N>.GB'` through
`RNASEQ_EXTRA_ARGS`, or set `RNASEQ_NEXTFLOW_CONFIG=/path/to/config`.

The generated samplesheet defaults to `strandedness=reverse`, matching the
production `reverse_stranded` featureCounts setting.

Alternatively, provide explicit references:

```bash
FASTA=/path/to/GRCh38.fa \
GTF=/path/to/genes.gtf \
STAR_INDEX=/path/to/star_index \
testdata-make/07-run-rnaseq-star-featurecounts
```

If explicit `FASTA` and `GTF` values are not set and the GENCODE primary
assembly files from `00-download-reference` are present, the rnaseq runner uses
them automatically with `--igenomes_ignore`. Set `GENOME` only when you
intentionally want nf-core/rnaseq to use an iGenomes reference instead.

This script intentionally uses `nf-core/rnaseq`, not `nf-core/sarek`. The
RNA-specific STAR, featureCounts, `--save_unaligned`, and Salmon/pseudoalignment
controls are part of nf-core/rnaseq; nf-core/sarek is a DNA variant-calling
pipeline and is not the correct tool for this RNA alignment/counting step.

The rnaseq run uses the Conda profile by default and expects `nextflow` to be
available in the active `nf-core` Conda environment. It writes under:

- `data/rna/rnaseq_samplesheet.csv`
- `data/rna/nf-core-rnaseq/rnaseq.params.json`
- `data/rna/nf-core-rnaseq/`
- `data/rna/work/`

After nf-core/rnaseq completes, create a compact RNA input bundle for
hlarnaseq. The script extracts the HLA interval from STAR-aligned BAMs, copies
paired unmapped FASTQs from the rnaseq results, writes per-sample gene count
tables, and writes the RNA manifest expected by hlarnaseq:

```bash
testdata-make/08-prepare-hlarnaseq-rna-inputs
```

Outputs:

- `data/hlarnases-testdata/rnaseq/rna_samples.csv`
- `data/hlarnases-testdata/rnaseq/hla_bam/<sample>.chr6_hla.GRCh38.bam`
- `data/hlarnases-testdata/rnaseq/hla_bam/<sample>.chr6_hla.GRCh38.bam.bai`
- `data/hlarnases-testdata/rnaseq/unmapped_fastq/<sample>.unmapped_1.fastq.gz`
- `data/hlarnases-testdata/rnaseq/unmapped_fastq/<sample>.unmapped_2.fastq.gz`
- `data/hlarnases-testdata/rnaseq/gene_counts/<sample>.gene_counts.tsv`

The script assumes these exact nf-core/rnaseq output paths:

- `star_salmon/<sample>.markdup.sorted.bam`
- `star_salmon/unmapped/<sample>.unmapped_1.fastq.gz`
- `star_salmon/unmapped/<sample>.unmapped_2.fastq.gz`
- `star_salmon/salmon.merged.gene_counts.tsv`

The compact gene count tables are derived from
`star_salmon/salmon.merged.gene_counts.tsv` and contain:

```text
gene_id	read_count
```

These counts are Salmon-derived estimated gene counts, not raw featureCounts
counts, and may contain fractional values.

The manifest has the columns:

```text
rna_sample_id,genome_sample_id,star_bam_path,gene_counts_path,unmapped_fastq_r1,unmapped_fastq_r2
```

In this compact manifest, `star_bam_path` points to the extracted HLA-region
BAM, not the full STAR genome BAM in the nf-core/rnaseq output directory.

Useful overrides:

- `FINAL_TESTDATA_DIR`: final compact bundle root; defaults to `data/hlarnases-testdata`.
- `REFERENCE_DIR`: reference genome and annotation output directory; defaults to `data/hlarnases-testdata/reference`.
- `HLA_DIR`: final WGS HLA-region BAM output directory; defaults to `data/hlarnases-testdata/wgs`.
- `RNA_FASTQ_ROOT`: directory containing downloaded paired FASTQs.
- `RNA_DOWNLOAD_DIR`: output directory for `05-download-na12878-rna`; defaults to `data/gm12878_rnaseq_fastq` below `testdata-make/`.
- `RNASEQ_SAMPLESHEET`: output path for the nf-core/rnaseq samplesheet.
- `RNASEQ_OUTDIR`: nf-core/rnaseq output directory.
- `RNASEQ_WORKDIR`: Nextflow work directory for the rnaseq run.
- `RNASEQ_PARAMS_FILE`: JSON params file used for nf-core/rnaseq options; defaults to `testdata-make/rnaseq.params.json`.
- `RNASEQ_NEXTFLOW_CONFIG`: Nextflow resource config; defaults to `testdata-make/rnaseq.nextflow.config`.
- `RNASEQ_REVISION`: nf-core/rnaseq revision passed with `-r`.
- `RNASEQ_EXTRA_ARGS`: additional arguments appended to the nf-core/rnaseq command.
- `GENOME`: optional nf-core/rnaseq iGenomes ID override.
- `HLA_REGION`: override the HLA interval; defaults to `chr6:28510120-33480577`.
- `GENOME_SAMPLE_ID`: genome sample ID written to `rna_samples.csv`; defaults to `NA12878`.
- `RNA_HLARNASEQ_DIR`: final RNA compact bundle directory; defaults to `data/hlarnases-testdata/rnaseq`.
- `RNA_UNMAPPED_FASTQ_DIR`: compact output directory for copied unmapped FASTQs; defaults to `data/hlarnases-testdata/rnaseq/unmapped_fastq`.
- `RNA_GENE_COUNTS_DIR`: compact output directory for per-sample gene count tables; defaults to `data/hlarnases-testdata/rnaseq/gene_counts`.
