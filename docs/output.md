# nf-core/hlarnaseq: Output

## Introduction

This document describes the output produced by the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

<!-- TODO nf-core: Write this documentation describing your workflow's output -->

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [arcasHLA read extraction and validation](#arcashla-read-extraction-and-validation) - Prepare and validate paired RNA reads for arcasHLA genotyping
- [arcasHLA genotyping](#arcashla-genotyping) - HLA genotyping from validated RNA-seq reads
- [HLA-LA](#hla-la) - HLA typing from WGS BAM inputs
- [HLA consensus](#hla-consensus) - RNA/WGS HLA consensus calling
- [HLA personalized reference (HLApm)](#hla-personalized-reference-hlapm) - Personalized HLA reference building from consensus alleles
- [HLApm STAR index](#hlapm-star-index) - Deduplicated STAR genome indexing of personalized HLA allele references
- [HLApm STAR alignment](#hlapm-star-alignment) - STAR alignment of RNA reads against personalized per-sample-per-allele indexes
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### arcasHLA read extraction and validation

<details markdown="1">
<summary>Output files</summary>

- `arcashla/extracted/`
  - `<rna_id>.mhc_1.fq.gz`: supplied read-1 FASTQ combined with complete BAM read pairs overlapping `--hla_region`.
  - `<rna_id>.mhc_2.fq.gz`: supplied read-2 FASTQ combined with complete BAM read pairs overlapping `--hla_region`.
- `arcashla/validation/`
  - `<rna_id>.validatefastq.log`: pairing-validation report for the extracted FASTQ files.

</details>

The extracted files are concatenated gzip streams and are accepted by standard gzip-aware FASTQ readers. They are forwarded only after `validatefastq` confirms the mates have consistent names, order, and record structure. A validator command failure or reported `ERROR` stops the pipeline.

### arcasHLA genotyping

<details markdown="1">
<summary>Output files</summary>

- `arcashla/genotype/`
  - `<rna_id>.genotype.json`: arcasHLA genotype calls for the sample.
  - `<rna_id>.genotype.log`: arcasHLA genotype run log for the sample.
- `arcashla/`
  - `arcasHLA_combined.csv`: Combined arcasHLA genotype calls across all RNA samples, in long format with one row per HLA gene per sample and columns `HLA_gene,allele1_rna,allele2_rna,rna_sample_id`, covering a fixed list of 21 `HLA-*` genes (genes not reported for a sample are padded with `NA` alleles).

</details>

`arcasHLA genotype` runs on each sample's validated, extracted read pair, requesting the genes listed in `--arcashla_genes`. Genotyping runs inside a dedicated, operator-prepared `arcas-hla` Conda environment rather than the pipeline's main environment (see [usage docs](usage.md) for details); this pipeline never builds or updates the arcasHLA reference itself.

### HLA-LA

<details markdown="1">
<summary>Output files</summary>

- `hlala/`
  - `HLA-LA_combined.tsv`: Combined HLA-LA G-group allele calls across all WGS samples, tab-separated with columns `sample_id`, `Locus`, `HLA_allele` (one allele per row, extracted from columns 1 and 3 of each sample's `R1_bestguess_G.txt`).
  - `<sample_id>/R1_bestguess_G.txt`: Per-sample HLA-LA G-group best guess file.
  - `<sample_id>/R1_bestguess.txt`: Per-sample HLA-LA best guess file, when produced by HLA-LA.
  - `<sample_id>/hla.tar.gz`: Archive of the per-sample HLA-LA `hla/` result directory, when produced.
  - `<sample_id>/hlala.log`: HLA-LA run log for the sample.

</details>

HLA-LA runs only when `--wgs_samples` is provided.
The combined CSV preserves the WGS sample identifiers from the `WGS_sample_id` column and extracts allele calls from column 3 of each `R1_bestguess_G.txt` after the header.

### HLA consensus

<details markdown="1">
<summary>Output files</summary>

- `hla_consensus/`
  - `hla_consensus.rna_wgs_rna-hla_with_consensus.tsv`: one row per (RNA sample, HLA gene), with columns `WGS_sample_ID`, `RNA_sample_ID`, `HLA_gene`, `consensus_alleles`, `consensus_level`, `consensus_labels`, `RNA_alleles`, `WGS_alleles`. `WGS_sample_ID` is the matched WGS sample ID from `--sample_key`, or a synthetic `RNA_ONLY:<RNA_sample_ID>` group when the RNA sample is absent from the key. Rows with an empty consensus call are dropped.
  - `hla_consensus.rna_wgs_hla_consensus.tsv`: one row per (WGS group, HLA gene), with columns `WGS_sample_ID`, `HLA_gene`, `consensus_level`, `consensus_labels`, `consensus_alleles`. This is the deduplicated consensus call per WGS group/gene (RNA replicates collapsed).

</details>

`HLA_CONSENSUS` runs automatically when `--rna_samples`, `--wgs_samples`, and `--sample_key` are all provided (no dedicated boolean flag). It combines the `arcashla/arcasHLA_combined.csv` RNA genotype calls with the `hlala/HLA-LA_combined.tsv` WGS genotype calls via the RNA/WGS mapping supplied with `--sample_key`, and applies a decision tree (`consensus_level` 1-4, `consensus_labels`) to call a consensus HLA allele set per WGS group and gene, preferring WGS calls when RNA and WGS agree or partially agree, and falling back to RNA-only consensus when no matched WGS sample or WGS genotype exists. `--hla_consensus_truncate_fields` controls the HLA resolution used for comparison (default 2 fields, e.g. `02:07`). `--rna_excluded_samples`/`--wgs_excluded_samples` optionally drop specific samples from consensus calling.

### HLA personalized reference (HLApm)

<details markdown="1">
<summary>Output files</summary>

- `hlapm/input/`
  - `<WGS_sample_ID>.tsv`: per-individual, 2-column HLApm input (`individual_ID`, `HLA_allele`), derived from `hla_consensus.rna_wgs_hla_consensus.tsv`. Loci outside `--hlapm_allowed_loci` simply do not appear in this file; no separate audit file is produced.
- `hlapm/personalized_ref/out/`
  - `<individual_ID>/<allele>.fa`, `<individual_ID>/<allele>.gtf`: HLApm's native personalized-reference output layout (one FASTA and one GTF per allele per individual), published as-is.

</details>

`HLAPM` runs automatically whenever `HLA_CONSENSUS` runs, i.e. whenever `--rna_samples`, `--wgs_samples`, and `--sample_key` are all provided; there is no separate flag to enable it. `--hlapm_repo` is mandatory in this case: the pipeline fails fast if it is missing or does not exist. It first converts the `hla_consensus.rna_wgs_hla_consensus.tsv` consensus calls into one per-individual HLA allele-list TSV per WGS group (including synthetic `RNA_ONLY:<rna_id>` groups), filtered by the `--hlapm_allowed_loci` allow-list, then builds a personalized FASTA+GTF reference per allele, per individual, using [HLApm](https://github.com/davenportlab/HLApm)'s `bulkRNA_build_personalized_HLA_ref()` function, run inside a dedicated, operator-prepared `hlapm` Conda environment (see [usage docs](usage.md) for details). This iteration stops at reference building; HLApm's downstream STAR-index/mapping/allele-assignment stages and single-cell mode are out of scope.

### HLApm STAR index

<details markdown="1">
<summary>Output files</summary>

- `hlapm/star_index_targets/`
  - `unique_alleles.csv`: one row per distinct allele reference (`allele_key`, `representative_name`, `fasta`, `gtf`), discovered by scanning the actual `hlapm/personalized_ref/out/<individual_ID>/*.fa`/`*.gtf` files on disk (not any consensus/HLApm-input TSV) and deduplicated by a content hash (sha256) of each allele's FASTA+GTF. `allele_key` is `<representative_name>__<8-character hash prefix>`.
  - `sample_alleles.csv`: one row per original `(individual_ID, allele)` occurrence (`sample`, `allele`, `allele_key`), mapping every individual's allele back to the shared `allele_key` it was indexed under. Use this file to find which `hlapm/star_index/<allele_key>/` directory applies to a given individual/allele - there is no per-individual STAR index directory.
- `hlapm/star_index/`
  - `<allele_key>/star/`: STAR genome index (`Genome`, `SA`, `SAindex`, etc.) for one distinct allele reference, built with `STAR --runMode genomeGenerate --sjdbOverhang 100`. Shared across every individual whose allele has that exact FASTA+GTF content, so a recurring allele (e.g. a common population allele) is indexed only once regardless of how many individuals carry it.

</details>

STAR indexing runs immediately after `HLAPM` builds the personalized references, deduplicating allele references by content (not by name) before indexing: HLApm's personalized-reference building does not explicitly guarantee that the same named allele call (e.g. `A*01:136`) is always byte-identical across individuals, so trusting name equality alone would risk silently indexing two different sequences as one. Indexing itself reuses the [nf-core/modules `STAR_GENOMEGENERATE`](https://github.com/nf-core/modules/tree/master/modules/nf-core/star/genomegenerate) module unmodified, pinned to STAR 2.7.11b (the version used by [nf-core/rnaseq](https://nf-co.re/rnaseq/) to build this pipeline's RNA-seq test data). Unlike the rest of this pipeline, STAR is not expected from an operator-prepared Conda environment: run the pipeline with `-profile singularity` (or `docker`/`conda`) so Nextflow can resolve STAR from the module's pinned container or `environment.yml` (see [usage docs](usage.md) for details). Aligning reads against these indexes is the next step, described immediately below.

### HLApm STAR alignment

<details markdown="1">
<summary>Output files</summary>

- `hlapm/star_align/`
  - `rna_sample_alleles.csv`: one row per resolved `(rna_id, sample, allele, allele_key)` alignment target (`rna_id,sample,allele,allele_key`) - `sample` keeps the original `HLA_CONSENSUS` grouping id (WGS individual ID, or `RNA_ONLY:<rna_id>`) alongside the real RNA sample id it was resolved to via `--sample_key`, for traceability. This is the human-facing summary of exactly which personalized alleles are (or were) aligned for each RNA sample.
  - `<rna_id>/<allele_key>/`: STAR alignment output for one `(RNA sample, allele)` pair, produced with `STAR --outSAMtype BAM SortedByCoordinate`:
    - `<rna_id>.<allele_key>.sortedByCoord.out.bam`: coordinate-sorted alignment of that RNA sample's arcasHLA MHC-extracted reads against that single allele's STAR index.
    - `<rna_id>.<allele_key>.Log.final.out`, `.Log.out`, `.Log.progress.out`: STAR's standard log outputs.

</details>

For every RNA sample that has one or more personalized HLA allele references, the pipeline aligns that sample's arcasHLA MHC-extracted reads (`ARCASHLA`'s `.mhc_1.fq.gz`/`.mhc_2.fq.gz`, not the full/raw RNA fastqs) against every one of its allele-specific STAR indexes: one alignment job per `(RNA sample, allele)` pair, so a sample with N personalized alleles produces N separate alignments that each reuse the same read pair against a different single-allele index.

`hlapm/star_index_targets/sample_alleles.csv`'s `sample` column is keyed by `HLA_CONSENSUS`'s grouping id (the WGS individual ID for WGS-backed individuals, or a synthetic `RNA_ONLY:<rna_id>` token otherwise), not directly by RNA sample id. Before alignment, this is resolved back to real RNA sample ids using `--sample_key`: `RNA_ONLY:<rna_id>` rows resolve by prefix-stripping alone, while WGS-individual rows broadcast-join against every RNA sample `--sample_key` matches to that individual - a WGS individual matched to more than one RNA sample has its full allele set aligned separately against each of those RNA samples' own reads, rather than collapsed to one. The resolved mapping is published as `rna_sample_alleles.csv` above.

This step reuses the [nf-core/modules `STAR_ALIGN`](https://github.com/nf-core/modules/tree/master/modules/nf-core/star/align) module unmodified, pinned to the same STAR 2.7.11b version used for indexing, and continues the same container/Conda exception described above. This iteration stops at producing per-sample-per-allele BAMs; HLA expression quantification from those BAMs, and reconciling alignments across candidate alleles into a single per-locus call, are out of scope.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
