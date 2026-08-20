# nf-core/hlarnaseq: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/hlarnaseq/usage](https://nf-co.re/hlarnaseq/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

<!-- TODO nf-core: Add documentation about anything specific to running your pipeline. For general topics, please point to (and add to) the main nf-core website. -->

## RNA samplesheet input

Provide the required RNA manifest with `--rna_samples` and the region to extract with `--hla_region`:

```bash
--rna_samples '[path to RNA samplesheet]' \
--hla_region 'chr6:28500000-33400000'
```

The CSV header must exactly match the following five columns:

```csv title="rna_samples.csv"
rna_id,bam,bai,unpaired_r1,unpaired_r2
RNA_SAMPLE_1,/path/to/RNA_SAMPLE_1.bam,/path/to/RNA_SAMPLE_1.bam.bai,/path/to/RNA_SAMPLE_1.unpaired_1.fastq.gz,/path/to/RNA_SAMPLE_1.unpaired_2.fastq.gz
```

| Column        | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| `rna_id`      | Unique RNA sample identifier without spaces.                                                          |
| `bam`         | Coordinate-sorted RNA-seq BAM containing aligned reads; must end in `.bam`.                           |
| `bai`         | Index for `bam`; must end in `.bai`.                                                                  |
| `unpaired_r1` | Gzip-compressed read-1 FASTQ to combine with BAM-derived MHC reads; must end in `.fq.gz`/`.fastq.gz`. |
| `unpaired_r2` | Gzip-compressed read-2 FASTQ to combine with BAM-derived MHC reads; must end in `.fq.gz`/`.fastq.gz`. |

All columns are mandatory and each `rna_id` may occur only once. Relative file paths are resolved from the samplesheet directory, launch directory, or pipeline project directory. The extraction is paired-end only.

`--hla_region` is passed unchanged to samtools. The user must choose coordinates and chromosome notation that match every BAM header: the pipeline does not translate `6` to `chr6`, or vice versa.

For each sample, the pipeline extracts complete pairs overlapping this region, excludes secondary and supplementary alignments, and combines the recovered mates with the supplied FASTQs. An [example RNA samplesheet](../assets/rna_samples.csv) is included.

Each extracted read pair is checked with `validatefastq` before it is made available to downstream arcasHLA steps. A non-zero validator exit status or a reported `ERROR` stops the pipeline; the pipeline does not attempt to repair, reorder, or skip invalid pairs. Successful per-sample validation logs are written beneath `arcashla/validation/`.

Once a sample's extracted reads pass validation, the pipeline runs `arcasHLA genotype` on them, requesting the genes listed in `--arcashla_genes` (a broad default gene list is provided). Per-sample results are written to `arcashla/genotype/<rna_id>.genotype.json` (+ `.log`).

### arcasHLA genotyping environment

`arcasHLA genotype` is invoked inside a dedicated Conda environment named `arcas-hla`, separate from the pipeline's main runtime environment. This environment is an **operator-prepared precondition**: the pipeline does not create it, install packages into it, or build/update its reference at any point. Before running the pipeline with RNA samples, prepare this environment yourself with:

- `arcas-hla=0.6.0`
- `kallisto=0.44` (later kallisto versions are incompatible with this arcasHLA version's `kallisto pseudo` output parsing)
- a reference built via `arcasHLA reference` (IMGT/HLA database + kallisto index)

The pipeline does not support redirecting `arcasHLA genotype` to a different reference at runtime; the reference used is whichever one is built into the `arcas-hla` environment.

## WGS samplesheet input

Optionally provide WGS BAM inputs with `--wgs_samples`:

```bash
--wgs_samples '[path to WGS samplesheet file]'
```

The WGS samplesheet must be a comma-separated file with exactly these columns:

```csv title="wgs_samples.csv"
WGS_sample_id,WGS_BAM_path,WGS_BAI_path
NA12878,testdata-make/hlarnases-testdata/wgs/NA12878.chr6_hla.GRCh38.bam,testdata-make/hlarnases-testdata/wgs/NA12878.chr6_hla.GRCh38.bam.bai
```

| Column          | Description                                                                |
| --------------- | -------------------------------------------------------------------------- |
| `WGS_sample_id` | WGS sample identifier. This entry is mandatory and cannot contain spaces.  |
| `WGS_BAM_path`  | Path to the WGS BAM file. This entry is mandatory and must end in `.bam`.  |
| `WGS_BAI_path`  | Path to the WGS BAI index. This entry is mandatory and must end in `.bai`. |

Each row is validated and loaded as a separate WGS sample channel entry. Relative BAM and BAI paths are resolved from the directory containing the WGS samplesheet, the launch directory, or the pipeline project directory. An [example WGS samplesheet](../assets/wgs_samples.csv) has been provided with the pipeline.

When `--wgs_samples` is provided, the pipeline runs HLA-LA once per WGS BAM and combines the reported G-group allele calls into `hlala/HLA-LA_combined.tsv`.
HLA-LA, samtools, and the prepared HLA-LA graph data must already be available in the active runtime environment.
The pipeline does not download, prepare, or package HLA-LA graph data in this early development stage.

Provide the parent directory containing the prepared graph with `--hlala_graph_dir`.
The graph name defaults to `PRG_MHC_GRCh38_withIMGT` and can be changed with `--hlala_graph`.

```bash
nextflow run nf-core/hlarnaseq \
    --rna_samples ./rna_samples.csv \
    --hla_region chr6:28500000-33400000 \
    --wgs_samples ./wgs_samples.csv \
    --hlala_graph_dir /path/to/HLA-LA/graphs \
    --outdir ./results
```

## RNA/WGS sample key input

`--sample_key` is a required top-level parameter whenever `--rna_samples` is provided. It maps RNA samples to their matched WGS sample (when one exists) for HLA consensus calling:

```bash
--sample_key '[path to sample key file]'
```

The sample key must be a comma-separated file with exactly these columns:

```csv title="sample_key.csv"
rnaseq_sample_id,wgs_sample_id
RNA_SAMPLE_1,WGS_SAMPLE_1
```

| Column             | Description                                                          |
| ------------------- | --------------------------------------------------------------------- |
| `rnaseq_sample_id`  | RNA sample identifier; must match a `rna_id` from `--rna_samples`.     |
| `wgs_sample_id`     | WGS sample identifier; must match a `WGS_sample_id` from `--wgs_samples`. |

One row per RNA sample that has a matched WGS sample. An RNA sample simply absent from this file (or, when `--wgs_samples` is not provided at all, every RNA sample) is treated as having no WGS pairing: it is reported under a synthetic `RNA_ONLY:<rna_id>` group instead of being matched to a WGS sample. A `--sample_key` file with zero data rows is valid and simply routes every RNA sample through the `RNA_ONLY:<rna_id>` fallback.

`HLA_CONSENSUS` runs automatically whenever `--rna_samples` (and therefore `--sample_key`) are provided; there is no separate flag to enable it. `--wgs_samples` is optional and only affects whether WGS-derived alleles are available to blend into the consensus call for matched individuals - it does not affect whether `HLA_CONSENSUS` (or the downstream HLApm/STAR steps) run at all. When `--wgs_samples` is not provided, `HLA_CONSENSUS` combines the arcasHLA RNA genotype calls with an empty HLA-LA input, so every group falls back to `RNA_ONLY:<rna_id>` and the consensus call is RNA-only.

Two further optional parameters let you drop specific samples from consensus calling without editing the RNA/WGS/HLA-LA inputs themselves:

- `--rna_excluded_samples`: path to a plain-text file listing RNA sample IDs (one per line) to exclude.
- `--wgs_excluded_samples`: path to a plain-text file listing WGS sample IDs (one per line) to exclude.

`--hla_consensus_truncate_fields` (default `2`) controls how many colon-separated fields of each HLA allele are kept when comparing RNA and WGS calls (e.g. `02:07:01` truncated to 2 fields becomes `02:07`).

## HLApm personalized HLA reference

`HLAPM` runs automatically whenever `HLA_CONSENSUS` runs, i.e. whenever `--rna_samples` (and therefore `--sample_key`) are provided, regardless of whether `--wgs_samples` is also provided; there is no separate flag to enable it. It converts the `hla_consensus.rna_wgs_hla_consensus.tsv` consensus calls into one per-individual HLA allele-list TSV, then builds a personalized FASTA+GTF reference per allele, per individual, using [HLApm](https://github.com/davenportlab/HLApm)'s `bulkRNA_build_personalized_HLA_ref()` function. It does not run HLApm's own downstream STAR-index/mapping/allele-assignment stages, and single-cell mode is out of scope; instead, the pipeline runs its own STAR indexing step immediately afterwards (see below).

`--hlapm_repo` is **mandatory** whenever `--rna_samples` is provided (mirroring the existing `--hlala_graph_dir` requirement above), independent of `--wgs_samples`: the pipeline fails fast with a clear error if it is missing or does not exist, rather than silently skipping the step.

```bash
--hlapm_repo '[path to a local HLApm checkout]'
```

`--hlapm_repo` must point to a local, pre-cloned checkout of [davenportlab/HLApm](https://github.com/davenportlab/HLApm) (including its bundled `data/references/` files). The pipeline never clones or fetches HLApm at runtime; the checkout must already exist at this path before the pipeline runs.

`--hlapm_allowed_loci` (default `A,B,C,DRB1,DQA1,DQB1,DPA1,DPB1,DOA,DOB,G,E,F`) is a comma-separated allow-list of HLA loci (without the `HLA-` prefix) to include when building the HLApm input. `HLA_CONSENSUS` output loci not in this list (e.g. `HLA-DRB3`, `HLA-H`, `HLA-J`, `HLA-K`, `HLA-L`) are silently omitted from the per-individual HLApm input TSVs; no separate audit/log file is written for excluded loci. This default is restricted to the loci HLApm's own per-allele locus regex can reliably parse — passing other loci through can crash the underlying R script.

### HLApm Conda environment

Building the personalized reference is invoked inside a dedicated Conda environment named `hlapm`, separate from the pipeline's main runtime environment. This environment is an **operator-prepared precondition**, worded like the `arcas-hla`/HLA-LA sections above: the pipeline does not create it, install packages into it, or update the HLApm checkout at any point. Before running the pipeline with `--rna_samples` (and therefore `--sample_key`), prepare this environment yourself with:

- R >= 4.1.0
- CRAN packages `data.table`, `dplyr`, `stringr`, `seqinr`
- Bioconductor packages `Biostrings`, `rtracklayer`, `DECIPHER`

### HLApm STAR index

Immediately after `HLAPM` builds the personalized FASTA+GTF references, the pipeline builds a STAR genome index for every allele reference that actually exists under `hlapm/personalized_ref/out/<individual_ID>/*.fa` - the set of alleles indexed is discovered by scanning that output tree directly, not from the HLApm input TSV or the consensus calls, since HLApm can emit reference files for alleles not listed in its own input. Before indexing, allele references are deduplicated by a content hash (sha256 of FASTA+GTF): the same allele often recurs across multiple individuals, and hashing content (rather than trusting the allele name) avoids ever silently merging two different sequences that happen to share a name. See [output docs](output.md#hlapm-star-index) for the resulting `hlapm/star_index/` and `hlapm/star_index_targets/` layout, including how to look up which shared index applies to a given individual/allele via `sample_alleles.csv`.

This step reuses the [nf-core/modules `STAR_GENOMEGENERATE`](https://github.com/nf-core/modules/tree/master/modules/nf-core/star/genomegenerate) module unmodified, pinned to **STAR 2.7.11b** - the same version used by [nf-core/rnaseq](https://nf-co.re/rnaseq/) to build this pipeline's own RNA-seq test data. Unlike arcasHLA/HLA-LA/HLApm above, STAR is **not** expected to already be available in an operator-prepared Conda environment on `$PATH`: run the pipeline with a container profile so Nextflow resolves STAR from the module's pinned container instead:

```bash
-profile singularity
```

`docker` works the same way. As a fallback, `-profile conda` lets Nextflow auto-create an isolated Conda environment from the module's pinned `environment.yml` (`bioconda::star=2.7.11b`) at run time instead of using a container; this has not been verified as thoroughly on all systems, so `singularity`/`docker` is recommended. This is a deliberate, scoped exception to this pipeline's general early-stage policy of assuming all tools come from an already-active Conda environment - every other step in the pipeline is unaffected.

### HLApm STAR alignment

Immediately after the STAR indexes are built, the pipeline aligns each RNA sample's arcasHLA MHC-extracted reads (`ARCASHLA`'s `.mhc_1.fq.gz`/`.mhc_2.fq.gz`, not the full/raw RNA fastqs) against every one of that sample's personalized allele indexes. This produces one alignment job per `(RNA sample, allele)` pair: a sample with 3 personalized alleles gets 3 separate STAR alignments, each reusing the same read pair against a different single-allele index.

`sample_alleles.csv`'s `sample` column is keyed by `HLA_CONSENSUS`'s grouping id (the WGS individual ID for WGS-backed individuals, or a synthetic `RNA_ONLY:<rna_id>` token otherwise) - not directly by RNA sample id. Before alignment, the pipeline resolves this back to real RNA sample ids using `--sample_key`: a WGS individual matched to more than one RNA sample in `--sample_key` has its full allele set aligned separately against each of those RNA samples' own reads (broadcast, not collapsed to one). This resolved mapping is published as `hlapm/star_align/rna_sample_alleles.csv` - see [output docs](output.md#hlapm-star-alignment) for its columns and for the alignment output layout.

This step reuses the [nf-core/modules `STAR_ALIGN`](https://github.com/nf-core/modules/tree/master/modules/nf-core/star/align) module unmodified, pinned to the same **STAR 2.7.11b** version used for indexing above, and continues the same container/Conda exception described there (`-profile singularity`/`docker`/`conda`).

### HLApm read quantification

Immediately after alignment, each per-`(RNA sample, allele)` coordinate-sorted BAM (`STAR_ALIGN`'s own output, above) is additionally queryname-sorted with [nf-core/modules `SAMTOOLS_SORT`](https://github.com/nf-core/modules/tree/master/modules/nf-core/samtools/sort) (`samtools sort -n`); `STAR_ALIGN`'s coordinate-sorted BAM is unchanged and continues to be published as before. Once every distinct allele's GTF (from HLApm STAR index, above) has been concatenated into one cohort-wide `combined.gtf` (comment lines stripped), the pipeline runs the legacy, unmodified Python 2.7 `make_a_table_210804_allHLAgenes.py` script once per RNA sample, over that sample's full set of per-allele queryname-sorted BAMs plus the combined GTF. For each read, this script assigns it to a gene by minimum summed-mate edit distance across every candidate allele/gene it overlaps, producing `<rna_id>.edit_distance.tsv` (one row per read, with a `unique`/`best`/`ambiguous` confidence label) plus a `<rna_id>.stat.txt` run-statistics log. See [output docs](output.md#hlapm-read-quantification) for the resulting `hlapm/quantify/` layout.

Immediately after `make_a_table_210804_allHLAgenes.py` writes `<rna_id>.edit_distance.tsv`, the pipeline runs a new `HLAPM_SUMMARIZE_READCOUNTS` step over that same table, using a new `bin/summarize_hla_readcounts.R` script (adapted from `davenportlab/HLApm_farm_pipeline`'s summarization script). For each RNA sample, it keeps only non-`ambiguous` reads whose winning-gene edit distance is at or below `--hlapm_quantify_max_edit_distance` (default `16`, matching the source script's hardcoded threshold), then counts the surviving reads per gene, producing `<rna_id>.HLA_gene_summary.tsv` (columns: `gene_name`, `n_reads_mapping`). This closes the "stops at the per-read table" gap left open by the earlier iteration; it runs inside the same `hlapm-quantify` Conda environment as `make_a_table_210804_allHLAgenes.py` (see below).

`--hlapm_quantify_max_edit_distance` (default `16`) is passed straight through to this step as the maximum summed-mate edit distance (NM) a read may have and still count toward its assigned gene's read count.

Per-allele-level read counts and a cross-sample combined gene-count table remain out of scope for this iteration. A whole-genome `featureCounts` gene-count table is now produced independently (see [Whole-genome common-reference gene counts](#whole-genome-common-reference-gene-counts), below); `<rna_id>.edit_distance.tsv` (above, not the `HLA_gene_summary.tsv` produced here) is reconciled against the HLA-region-restricted half of that whole-genome work in [HLA read-count reconciliation diff table](#hla-read-count-reconciliation-diff-table), below.

#### `hlapm-quantify` Conda environment

Running `make_a_table_210804_allHLAgenes.py` and `summarize_hla_readcounts.R` are both invoked inside a dedicated Conda environment named `hlapm-quantify`, separate from the pipeline's main runtime environment. This environment is an **operator-prepared precondition**, worded like the `arcas-hla`/`hlapm` sections above: the pipeline does not create it or install packages into it at any point. Before running the pipeline with `--rna_samples` (and therefore `--sample_key`), prepare this environment yourself with:

- Python 2
- `pybam` (`pip install https://github.com/JohnLonginotto/pybam/zipball/master`)
- `intervaltree` (PyPI)
- R (>= 4.0, matching the `hlapm` env's floor)
- CRAN packages `dplyr`, `tidyr`

For example:

```bash
mamba install -n hlapm-quantify -c conda-forge r-base r-dplyr r-tidyr
```

## Whole-genome common-reference gene counts

Independent of `--sample_key`/HLApm, whenever `--rna_samples` is provided the pipeline also runs [nf-core/modules `SUBREAD_FEATURECOUNTS`](https://github.com/nf-core/modules/tree/master/modules/nf-core/subread/featurecounts) once per RNA sample, directly against that sample's original, full whole-genome, coordinate-sorted BAM (`--rna_samples`'s `bam`/`bai` columns) - not the arcasHLA MHC-extracted reads or HLApm personalized references used above. This reproduces, in-pipeline, the "original count matrix" half of the legacy prototype's `featureCounts` step, producing a per-sample whole-genome gene-count table without depending on an externally supplied count matrix file.

`--gtf` is **mandatory** whenever `--rna_samples` is provided (mirroring the existing `--hlapm_repo` requirement above): the pipeline fails fast with a clear error if it is missing or does not exist.

```bash
--gtf '[path to a whole-genome reference GTF]'
```

`--rnaseq_strandedness` (default `reverse`) sets the RNA-seq library strandedness passed to featureCounts (`-s`); allowed values are `unstranded`, `forward`, or `reverse`. This is a single pipeline-wide value, not a per-sample `--rna_samples` column - a future cohort needing per-sample strandedness would require revisiting this as a samplesheet column.

This step reuses the `SUBREAD_FEATURECOUNTS` module unmodified, pinned to **Subread 2.1.1**. As with `STAR_GENOMEGENERATE`/`STAR_ALIGN` above, Subread/featureCounts is **not** expected to already be available in an operator-prepared Conda environment on `$PATH`: run the pipeline with a container profile so Nextflow resolves it from the module's pinned container instead:

```bash
-profile singularity
```

`docker` works the same way. As a fallback, `-profile conda` lets Nextflow auto-create an isolated Conda environment from the module's pinned `environment.yml` (`bioconda::subread=2.1.1`) at run time instead of using a container; this has not been verified as thoroughly on all systems, so `singularity`/`docker` is recommended. This is the same deliberate, scoped exception to this pipeline's general early-stage policy already described for STAR above.

See [output docs](output.md#whole-genome-common-reference-gene-counts) for the resulting `counts_commonref/` layout. Patching these whole-genome counts with `HLAPM_STAR_QUANTIFY`'s HLA-specific counts (the final splice of the "hijack original count matrix" step) remains explicitly out of scope for this iteration; the per-gene reconciliation diff feeding that future step is produced by [HLA read-count reconciliation diff table](#hla-read-count-reconciliation-diff-table), below.

## HLA-region per-read featureCounts reconciliation input

Independent of `--sample_key`/HLApm, whenever `--rna_samples` is provided the pipeline also produces a per-read gene-assignment table for the HLA-region-restricted subset of each RNA sample's original BAM - the second of three steps so far toward the "hijack original count matrix" roadmap item. Unlike [Whole-genome common-reference gene counts](#whole-genome-common-reference-gene-counts) above (which is independent of/parallel to `ARCASHLA`), this step runs *after* `ARCASHLA`, because it reuses `ARCASHLA_EXTRACT`'s own intermediate HLA-region BAM (`arcashla/extracted/<rna_id>.mhc.namesort.bam`, see [output docs](output.md#arcashla-read-extraction-and-validation)) rather than extracting the HLA region a second time from scratch. No new region-extraction dependency is introduced by this step.

`SUBREAD_FEATURECOUNTS` (aliased `SUBREAD_FEATURECOUNTS_HLA`, a second invocation of the same vendored module used above) runs with `-R BAM` against that intermediate BAM and the same cohort-wide `--gtf` reference already used above - no separate HLA-only GTF is built or required. This module has been patched (`nf-core modules patch subread/featurecounts`) to additionally capture the `-R BAM` per-read reannotated BAM as a declared output (previously an unexposed side effect of `-R BAM`); the patch also fixes an unrelated, pre-existing version-reporting defect (see `CHANGELOG.md`). The reannotated BAM is then converted to plain text with `samtools view`, filtered to `Assigned`-status lines, and reformatted into a `read_name`, `direction`, `gene_name`, `edit_distance` TSV by a new `bin/reformat_rnaseq_featurecounts.py` script - both steps only require `samtools`/`python3` on `$PATH`, already operator-Conda-environment preconditions elsewhere in this pipeline (unlike `SUBREAD_FEATURECOUNTS_HLA` itself, which continues the same container/`-profile conda` exception as `SUBREAD_FEATURECOUNTS` above).

See [output docs](output.md#hla-region-per-read-featurecounts-reconciliation-input) for the resulting `counts_commonref_hla/` layout. This step itself stops at producing the per-read table; reconciling it against `HLAPM_STAR_QUANTIFY`'s HLA-specific `edit_distance.tsv` is described immediately below. The final splice into `counts_commonref`'s whole-genome table (the "hijack" step itself) remains out of scope for this iteration.

## HLA read-count reconciliation diff table

Whenever an RNA sample has both a `counts_commonref_hla` read-gene-assignment table (above) and a personalized-HLA `edit_distance.tsv` ([HLApm read quantification](#hlapm-read-quantification), above) - i.e. only samples resolved through `--sample_key`/HLApm to at least one personalized allele - the pipeline reconciles the two into a per-gene diff table, via a new `HLA_READCOUNT_RECONCILE` subworkflow (`HLA_READCOUNT_RECONCILE_DIFF` module) and a new `bin/reconcile_hla_readcounts.py` script. This is iteration 3 of the "hijack original count matrix" roadmap item: it adapts `artifacts/scripts/compare-hla-rnaseq-readcounts.py`'s read-pair reconciliation logic (kept-vs-dropped classification) to these two real pipeline tables. Samples not resolved to any personalized-HLA allele simply get no diff table - an expected inner-join outcome, not an error.

For every personalized-HLA read pair (after the existing `ambiguous`/`--hlapm_quantify_max_edit_distance` filtering, reusing the same threshold `HLAPM_SUMMARIZE_READCOUNTS` above uses), it is kept as HLA if the local `counts_commonref_hla` table has no matching read pair (`missing_fc`), if `counts_commonref_hla` also assigned it to an HLA gene (`both_hla`), or if `counts_commonref_hla` assigned it to a non-HLA gene but the personalized-reference edit distance is equal to or better (`reassigned_to_hla`); otherwise it is dropped in favor of the better non-HLA `counts_commonref_hla` assignment. Every post-filter personalized-HLA gene gets a row in the output - including a gene whose every read pair was dropped, with a reconciled count of `0` rather than a silently missing row (a gap fixed relative to the prototype script). A non-HLA gene only gets a row when it lost at least one read pair to HLA.

Every gene name in the output (HLA and non-HLA alike) is resolved to a `gene_id` via the whole-genome `--gtf` (unlike the separate `artifacts/scripts/hijack-original-featurecounts.py` prototype's own gene-mapping helper, which only resolves `HLA-`-prefixed names). Gene-id resolution never fails the run; instead it applies a soft, category-aware policy and records every problem in a dedicated, always-produced `<rna_id>.gene_id_resolution_warnings.tsv` file (see [output docs](output.md#hla-read-count-reconciliation-diff-table) for its full column schema), in addition to a batched stderr summary:

- A `gene_name` absent from `--gtf` resolves to the literal string `NA` - a personalized-reference-only or renamed gene symbol legitimately missing from the whole-genome GTF is plausible.
- A `gene_name` that maps to more than one distinct `gene_id` in `--gtf` (a real, non-hypothetical occurrence: GENCODE v50's primary assembly has 484 such ambiguous names, including 4 HLA genes themselves - `HLA-H`, `HLA-L`, `HLA-V`, `HLA-DRB6` - each a near-identical/overlapping-gene-row annotation-duplication artifact) is resolved deterministically instead of failing the run: an HLA-category row uses the first `gene_id` encountered while scanning `--gtf` (first-appearance order, not resolved alphabetically or by iteration order of a Python `set`); a non-HLA-category row instead keeps **every** candidate `gene_id`, semicolon-joined in that same first-appearance order (e.g. `ENSG00000236397.3;ENSG00000308415.1;ENSG00000310539.1`), so no candidate id is silently dropped.

This reconciliation - and the ambiguous-`gene_id` resolution above - operates entirely at `gene_name` granularity, never `gene_id`: the per-read `gene_id` featureCounts originally assigned (via its `XT` tag) is already discarded upstream, when [`bin/reformat_rnaseq_featurecounts.py`](#hla-region-per-read-featurecounts-reconciliation-input) converts it to `gene_name` (above) - `counts_commonref_hla`'s own per-read table never carries `gene_id` at all, so this step has no per-read `gene_id` left to work with even for a non-HLA row. This is not just an incidental data-loss inconvenience: featureCounts assigns each mate of a read pair independently, based on that mate's own overlap, so for two overlapping gene annotations that happen to share one `gene_name` (exactly the kind of annotation-duplication artifact described above - `POLR1HASP`'s two `gene_id`s are one real example: a large lncRNA locus with a smaller pseudogene entirely nested inside its span), a read pair's R1 and R2 mates can each be assigned a *different* specific `gene_id` by featureCounts while still agreeing on `gene_name`. There is therefore no single, unambiguous `gene_id` to attribute a whole read pair to even in principle, which is why a non-HLA row's `original_fc_count`/`diff` (or an HLA row's `personalized_count`, which HLApm never associates with any whole-genome `gene_id` at all) is never split out per individual `gene_id` - the semicolon-joined-list/first-id policy above is the full extent of this step's `gene_id` resolution.

See [output docs](output.md#hla-read-count-reconciliation-diff-table) for the resulting `hla_readcount_reconcile/` layout and full column schema. This step produces only the per-sample diff table; merging/patching `counts_commonref`'s whole-genome table using this diff table (the final "hijack" splice) remains a future iteration.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run nf-core/hlarnaseq \
    --rna_samples ./rna_samples.csv \
    --hla_region chr6:28500000-33400000 \
    --outdir ./results
```

This early-stage pipeline expects samtools and validatefastq to be available in the active Conda environment, and a separate, dedicated `arcas-hla` Conda environment to be prepared as described above for arcasHLA genotyping.

> [!NOTE]
> `-profile test`'s bundled RNA fixture is deliberately tiny and does not carry real HLA allele signal, so arcasHLA genotypes it as empty. Since `HLA_CONSENSUS`, `HLAPM`, and STAR indexing/alignment are now mandatory whenever `--rna_samples`/`--sample_key` are provided, a real (non-stub) `-profile test` run will fail once it reaches `HLA_CONSENSUS`/`HLAPM` with no allele calls to consense. At this development stage, `-profile test` is validated with `-stub-run` (`nextflow run . -profile test -stub-run --outdir <OUTDIR>`), which proves process/channel wiring without needing real tool output. A real, non-stub `-profile test` run is not expected to succeed yet.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/hlarnaseq -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
rna_samples: './rna_samples.csv'
hla_region: 'chr6:28500000-33400000'
outdir: './results/'
genome: 'GRCh38'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/hlarnaseq
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/hlarnaseq releases page](https://github.com/nf-core/hlarnaseq/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/usage/configuration#max-resources) and [tuning workflow resources](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/usage/configuration#updating-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
