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
- [HLApm read quantification](#hlapm-read-quantification) - Queryname-sorted BAMs, cohort-wide combined GTF, per-read edit-distance/gene-assignment tables, and per-gene read-count summaries
- [Whole-genome common-reference gene counts](#whole-genome-common-reference-gene-counts) - Per-sample whole-genome featureCounts gene-count tables from each RNA sample's original BAM
- [HLA-region per-read featureCounts reconciliation input](#hla-region-per-read-featurecounts-reconciliation-input) - Per-read, per-sample gene assignment table from the HLA-region-restricted subset of each RNA sample's original BAM
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### arcasHLA read extraction and validation

<details markdown="1">
<summary>Output files</summary>

- `arcashla/extracted/`
  - `<rna_id>.mhc_1.fq.gz`: supplied read-1 FASTQ combined with complete BAM read pairs overlapping `--hla_region`.
  - `<rna_id>.mhc_2.fq.gz`: supplied read-2 FASTQ combined with complete BAM read pairs overlapping `--hla_region`.
  - `<rna_id>.mhc.namesort.bam`: the HLA-region-restricted, primary-alignment-only (secondary/supplementary excluded), name-sorted BAM slice of that sample's original BAM that `<rna_id>.mhc_1/2.fq.gz` are themselves derived from (before FASTQ conversion and merging with the supplied `unpaired_r1`/`unpaired_r2` reads). Published as a side effect of this file already being produced internally; it is also consumed directly by [HLA-region per-read featureCounts reconciliation input](#hla-region-per-read-featurecounts-reconciliation-input), below.
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

`HLA_CONSENSUS` runs automatically whenever `--rna_samples` (and therefore `--sample_key`, which is a required top-level parameter) are provided (no dedicated boolean flag), regardless of whether `--wgs_samples` is also provided. It combines the `arcashla/arcasHLA_combined.csv` RNA genotype calls with the `hlala/HLA-LA_combined.tsv` WGS genotype calls (or a header-only placeholder when `--wgs_samples` is not provided) via the RNA/WGS mapping supplied with `--sample_key`, and applies a decision tree (`consensus_level` 1-4, `consensus_labels`) to call a consensus HLA allele set per WGS group and gene, preferring WGS calls when RNA and WGS agree or partially agree, and falling back to RNA-only consensus (`RNA_ONLY:<rna_id>` groups) when no matched WGS sample, no WGS genotype, or no WGS data at all exists. `--hla_consensus_truncate_fields` controls the HLA resolution used for comparison (default 2 fields, e.g. `02:07`). `--rna_excluded_samples`/`--wgs_excluded_samples` optionally drop specific samples from consensus calling.

### HLA personalized reference (HLApm)

<details markdown="1">
<summary>Output files</summary>

- `hlapm/input/`
  - `<WGS_sample_ID>.tsv`: per-individual, 2-column HLApm input (`individual_ID`, `HLA_allele`), derived from `hla_consensus.rna_wgs_hla_consensus.tsv`. Loci outside `--hlapm_allowed_loci` simply do not appear in this file; no separate audit file is produced.
- `hlapm/personalized_ref/out/`
  - `<individual_ID>/<allele>.fa`, `<individual_ID>/<allele>.gtf`: HLApm's native personalized-reference output layout (one FASTA and one GTF per allele per individual), published as-is.

</details>

`HLAPM` runs automatically whenever `HLA_CONSENSUS` runs, i.e. whenever `--rna_samples` (and therefore `--sample_key`) are provided; there is no separate flag to enable it, and it runs regardless of whether `--wgs_samples` is also provided. `--hlapm_repo` is mandatory whenever `--rna_samples` is provided, independent of `--wgs_samples`: the pipeline fails fast if it is missing or does not exist. It first converts the `hla_consensus.rna_wgs_hla_consensus.tsv` consensus calls into one per-individual HLA allele-list TSV per WGS group (including synthetic `RNA_ONLY:<rna_id>` groups), filtered by the `--hlapm_allowed_loci` allow-list, then builds a personalized FASTA+GTF reference per allele, per individual, using [HLApm](https://github.com/davenportlab/HLApm)'s `bulkRNA_build_personalized_HLA_ref()` function, run inside a dedicated, operator-prepared `hlapm` Conda environment (see [usage docs](usage.md) for details). This iteration stops at reference building; HLApm's downstream STAR-index/mapping/allele-assignment stages and single-cell mode are out of scope.

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

This step reuses the [nf-core/modules `STAR_ALIGN`](https://github.com/nf-core/modules/tree/master/modules/nf-core/star/align) module unmodified, pinned to the same STAR 2.7.11b version used for indexing, and continues the same container/Conda exception described above. This iteration stops at producing per-sample-per-allele BAMs; reconciling alignments across candidate alleles into a single per-locus call remains out of scope. Read quantification from these BAMs, including gene-level read counts, is described immediately below (see [HLApm read quantification](#hlapm-read-quantification)).

### HLApm read quantification

<details markdown="1">
<summary>Output files</summary>

- `hlapm/star_align/<rna_id>/<allele_key>/`
  - `<rna_id>.<allele_key>.queryname.bam`: the same alignment as `<rna_id>.<allele_key>.sortedByCoord.out.bam` above, additionally sorted by read name (`samtools sort -n`) rather than coordinate. The coordinate-sorted BAM is unaffected and continues to be published as before.
- `hlapm/quantify/`
  - `combined.gtf`: every distinct allele's GTF (from `hlapm/star_index/<allele_key>/`) concatenated into one cohort-wide file, with comment lines stripped. Built once per pipeline run, not once per RNA sample.
  - `<rna_id>/<rna_id>.edit_distance.tsv`: one row per read observed across that sample's full set of per-allele queryname-sorted BAMs, with columns `read_name`, `gene_name_confidence` (`unique`/`best`/`ambiguous`), `gene_name`, followed by one column per input BAM holding that read's summed-mates edit distance (NM) when it belongs to the winning gene, else `NA`.
  - `<rna_id>/<rna_id>.stat.txt`: run-statistics log (redirected stderr) for that sample's quantification run.
  - `<rna_id>/<rna_id>.HLA_gene_summary.tsv`: per-gene read count derived from `<rna_id>.edit_distance.tsv`, with columns `gene_name` and `n_reads_mapping` (the number of non-`ambiguous` reads assigned to that gene with a winning-gene edit distance at or below `--hlapm_quantify_max_edit_distance`).

</details>

For every RNA sample, the pipeline queryname-sorts each of that sample's per-allele coordinate-sorted BAMs (`STAR_ALIGN`'s output, above) using the [nf-core/modules `SAMTOOLS_SORT`](https://github.com/nf-core/modules/tree/master/modules/nf-core/samtools/sort) module (`samtools sort -n`), then runs the legacy, unmodified Python 2.7 `make_a_table_210804_allHLAgenes.py` script once per RNA sample, over that sample's full set of queryname-sorted per-allele BAMs plus the cohort-wide `combined.gtf`. The script assigns each read to a gene by minimum summed-mate edit distance across every candidate allele/gene it overlaps, producing the per-read `edit_distance.tsv` table above. It runs inside a dedicated, operator-prepared `hlapm-quantify` Conda environment (see [usage docs](usage.md) for details).

A new `HLAPM_SUMMARIZE_READCOUNTS` step then turns that per-read table into the per-gene `<rna_id>.HLA_gene_summary.tsv` read-count summary described above, using a new `bin/summarize_hla_readcounts.R` script (adapted from `davenportlab/HLApm_farm_pipeline`'s summarization script) and the same `hlapm-quantify` Conda environment. Per-allele-level read counts and a cross-sample combined gene-count table remain out of scope for this iteration; see [Whole-genome common-reference gene counts](#whole-genome-common-reference-gene-counts), below, for an independently produced whole-genome `featureCounts` table, and [usage docs](usage.md#whole-genome-common-reference-gene-counts) for why reconciling the two is a future iteration.

### Whole-genome common-reference gene counts

<details markdown="1">
<summary>Output files</summary>

- `counts_commonref/<rna_id>/`
  - `<rna_id>.featureCounts.tsv`: featureCounts gene-count table for that RNA sample, produced by running featureCounts (`--countReadPairs -g gene_id`) directly against that sample's original, full whole-genome, coordinate-sorted BAM (`--rna_samples`'s `bam` column) and the whole-genome reference GTF supplied with `--gtf`.
  - `<rna_id>.featureCounts.tsv.summary`: featureCounts' own per-sample assignment summary log.

</details>

For every RNA sample, independent of `--sample_key`/HLApm, the pipeline runs the [nf-core/modules `SUBREAD_FEATURECOUNTS`](https://github.com/nf-core/modules/tree/master/modules/nf-core/subread/featurecounts) module unmodified, pinned to Subread 2.1.1, once per sample against that sample's own original BAM plus the single, cohort-wide `--gtf` reference. `--rnaseq_strandedness` (default `reverse`, pipeline-wide rather than per-sample) is merged into each sample's metadata immediately beforehand. This is **not yet reconciled** against `HLAPM_STAR_QUANTIFY`'s HLA-specific gene counts above - that reconciliation ("hijack original count matrix") is a future iteration. See [usage docs](usage.md#whole-genome-common-reference-gene-counts) for the container/`-profile conda` dependency this step introduces.

### HLA-region per-read featureCounts reconciliation input

<details markdown="1">
<summary>Output files</summary>

- `counts_commonref_hla/<rna_id>/`
  - `<rna_id>.rnaseq_featurecounts.tsv`: one row per HLA-region read assigned to a gene, with columns `read_name`, `direction` (`R1`/`R2`/`NA`), `gene_name`, `edit_distance`. This is an **intermediate artifact** for a future reconciliation step ("hijack original count matrix"), not a final HLA gene-count table.
  - `<rna_id>.featureCounts.tsv.summary`: featureCounts' own per-sample assignment summary log for this step's `-R BAM` run.

</details>

For every RNA sample, independent of `--sample_key`/HLApm, the pipeline runs `SUBREAD_FEATURECOUNTS` a second time (aliased as `SUBREAD_FEATURECOUNTS_HLA`) with `-R BAM`, directly against `arcashla/extracted/<rna_id>.mhc.namesort.bam` above (the HLA-region-restricted subset of that sample's original BAM, reused from `ARCASHLA_EXTRACT` rather than re-extracted) plus the same cohort-wide `--gtf` reference used above - no separate HLA-only GTF is built. The reannotated per-read BAM this produces is converted to plain text with `samtools view`, filtered to `Assigned`-status lines, and reformatted by a new `bin/reformat_rnaseq_featurecounts.py` script into the per-read TSV documented above. Reconciling this table against `HLAPM_STAR_QUANTIFY`'s HLA-specific `edit_distance.tsv` (above), and the final splice into `counts_commonref`'s whole-genome table, are both explicitly out of scope for this iteration - see [usage docs](usage.md#hla-region-per-read-featurecounts-reconciliation-input).

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
