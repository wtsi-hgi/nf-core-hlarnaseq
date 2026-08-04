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
