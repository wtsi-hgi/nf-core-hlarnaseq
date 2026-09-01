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

Each extracted read pair is checked with [validatefastq](https://github.com/biopet/validatefastq) before it is made available to downstream arcasHLA steps. A non-zero validator exit status or a reported `ERROR` stops the pipeline; the pipeline does not attempt to repair, reorder, or skip invalid pairs. Successful per-sample validation logs are written beneath `arcashla/validation/`.

`ARCASHLA_VALIDATE_FASTQ` provisions the validator itself, via its own module `environment.yml`/`conda` directive (`bioconda::biopet-validatefastq=0.1.1`) paired with the matching pinned Biocontainers image, resolved automatically under `-profile conda`/`docker`/`singularity`/`apptainer`. Nothing needs to be installed by hand, and no operator-prepared Conda environment is used for this step. Note that the packaged executable is named `biopet-validatefastq` (there is no plain `validatefastq` alias); running the pipeline with no container/Conda profile at all leaves the module unprovisioned and it will fail fast saying so.

Once a sample's extracted reads pass validation, the pipeline runs `arcasHLA genotype` on them, requesting the genes listed in `--arcashla_genes` (a broad default gene list is provided). Per-sample results are written to `arcashla/genotype/<rna_id>.genotype.json` (+ `.log`).

### arcasHLA genotyping environment

`ARCASHLA_GENOTYPE` provisions arcasHLA itself via its own module `environment.yml`/`conda` directive (`arcas-hla=0.6.0`, `kallisto=0.44.0` - later kallisto versions are incompatible with this arcasHLA version's `kallisto pseudo` output parsing), resolved automatically by Nextflow under `-profile conda`. No separate operator-prepared Conda environment is needed for this step.

arcasHLA has no option to point `genotype` at an external reference database at runtime; the reference used is always whichever one exists inside its own install. Rather than have the pipeline build this reference itself (it clones the ~4GB [ANHIG/IMGTHLA](https://github.com/ANHIG/IMGTHLA) database - too slow and network-dependent to do inside every container build or as a first-task surprise), it is prepared once, out of band, and pointed to with a required **`--arcashla_reference_dir`** parameter - the same pattern as `--hlala_graph_dir` for HLA-LA above. `ARCASHLA_GENOTYPE` symlinks this directory into place as its own `dat/ref` at the start of every task; the symlink swap is fast and atomic, so it's redone unconditionally on every task with no locking or "first use" logic.

Build the reference once with:

```bash
scripts/build_image_arcashla.sh              # build the container image, once
scripts/build_arcashla_reference.sh /path/to/arcashla_reference   # build the reference into it, once
```

`build_arcashla_reference.sh` runs inside the same container image the pipeline itself uses (so the reference matches the exact pinned `arcas-hla=0.6.0`/`kallisto=0.44.0` versions). It does not just run plain `arcasHLA reference`: as of IMGT/HLA's Release 3.56.0, its large files (including the `hla.dat` this arcasHLA version expects as a plain file) are distributed as separate `.zip` downloads rather than checked into git, which arcasHLA 0.6.0 doesn't know how to handle. Instead, the script clones IMGT/HLA itself and checks out a pinned pre-3.56.0 commit (IMGT/HLA version 3.46.0 by default - the newest version arcasHLA 0.6.0 has a built-in commit mapping for; override with `IMGTHLA_COMMIT`), then runs `arcasHLA reference --rebuild` against that pinned checkout. This also pins the exact HLA database version used, rather than depending on whatever the upstream default branch contains when the script happens to be run. It checks that a real `hla.idx` file was actually produced before finishing (arcasHLA can otherwise fail partway without a clear error). Then run the pipeline with:

```bash
--arcashla_reference_dir /path/to/arcashla_reference
```

The build needs roughly **15 GB of free space** and network access to `github.com`. It runs under Docker if that image is loaded, otherwise Singularity/Apptainer against the local `.sif`; `RUNTIME=docker|singularity|apptainer` forces one. Under Singularity/Apptainer all of that space is used on the output directory's own filesystem - a `.sif` is read-only at execution time, so the IMGT/HLA checkout cannot live inside the image the way it does in a Docker container's writable layer, and the script instead mounts a writable scratch directory over the image's arcasHLA `dat/` directory. That scratch directory defaults to a temporary `<output-dir>.build.XXXXXX` sibling, removed when the script exits; set `DAT_WORK_DIR` to put it on a different (larger) filesystem, in which case it is left in place. The free-space check runs before the download and can be adjusted with `REQUIRED_GB`. See `scripts/build_arcashla_reference.sh --help` for all override variables.

Under `-profile docker`/`-profile singularity`/`-profile apptainer`, `ARCASHLA_GENOTYPE` uses a container image built from `modules/local/arcashla/genotype/Dockerfile` (just the pinned packages - no reference baked in, for the same reason it isn't built automatically above). Build it once before running with a container profile:

```bash
scripts/build_image_arcashla.sh
```

This builds and tags the Docker image as `quay.io/hlarnaseq/arcashla-genotype:0.6.0`, matching `nextflow.config`'s `docker.registry`/`singularity.registry = 'quay.io'` default so `-profile docker` finds it locally with no registry push needed. It also converts that same image into a local `modules/local/arcashla/genotype/arcashla-genotype.sif` (when `singularity`/`apptainer` is available) for `-profile singularity`/`apptainer`: Singularity/Apptainer has no access to Docker's local image store, and a bare image name is not a filesystem path, so without this `.sif` file Nextflow would otherwise try (and fail) to pull the image from `quay.io` over the network. See `scripts/build_image_arcashla.sh --help` for details and override variables.

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

| Column          | Description                                                                                                          |
| --------------- | -------------------------------------------------------------------------------------------------------------------- |
| `WGS_sample_id` | WGS sample identifier. This entry is mandatory and cannot contain spaces.                                            |
| `WGS_BAM_path`  | Path to the WGS BAM file. This entry is mandatory and must end in `.bam`.                                            |
| `WGS_BAI_path`  | Path to the WGS BAI index. This entry is mandatory and must be named `<BAM file name>.bai` (i.e. end in `.bam.bai`). |

Each row is validated and loaded as a separate WGS sample channel entry. Relative BAM and BAI paths are resolved from the directory containing the WGS samplesheet, the launch directory, or the pipeline project directory. An [example WGS samplesheet](../assets/wgs_samples.csv) has been provided with the pipeline.

The index must be named exactly `<BAM file name>.bai` (for example `NA12878.bam` + `NA12878.bam.bai`), not `<BAM base name>.bai`: HLA-LA resolves a BAM's index by appending `.bai` to the BAM path, and will not find an index named otherwise. This is enforced by [`assets/schema_wgs_samples.json`](../assets/schema_wgs_samples.json), so a mismatch fails at samplesheet validation rather than deep inside HLA-LA.

When `--wgs_samples` is provided, the pipeline runs HLA-LA once per WGS BAM and combines the reported G-group allele calls into `hlala/HLA-LA_combined.tsv`.
HLA-LA itself (and the samtools/bwa/picard tooling it shells out to) is provisioned by the `HLALA_TYPING` module's own `environment.yml`/`conda` directive and matching pinned `container` (`hla-la=1.0.4`), resolved automatically by Nextflow under `-profile conda`/`docker`/`singularity`/`apptainer`. No separate operator-prepared Conda environment is needed for this step.

The prepared HLA-LA **graph**, however, remains a required, separately-prepared input: the pipeline never downloads, builds, or packages HLA-LA graph data (the `hlala/preparegraph` step is deliberately not wired in), the same pattern as `--arcashla_reference_dir` for arcasHLA above.
Provide the **parent** directory containing the prepared graph with `--hlala_graph_dir`, and the **graph directory's own name** with `--hlala_graph` (defaults to `PRG_MHC_GRCh38_withIMGT`) - i.e. the graph the pipeline uses is `<hlala_graph_dir>/<hlala_graph>`.

```bash
nextflow run nf-core/hlarnaseq \
    --rna_samples ./rna_samples.csv \
    --hla_region chr6:28500000-33400000 \
    --wgs_samples ./wgs_samples.csv \
    --hlala_graph_dir /path/to/HLA-LA/graphs \
    --outdir ./results
```

### Preparing the HLA-LA graph

Prepare the graph once, out of band, with:

```bash
scripts/build_reference_hlala.sh /path/to/HLA-LA/graphs
```

This downloads the published PRG graph package (`PRG_MHC_GRCh38_withIMGT`, ~2.25 GB), verifies its md5, extracts it, and indexes it (`HLA-LA --action prepareGraph`) inside the same pinned `hla-la:1.0.4` container image `HLALA_TYPING` itself runs - so the graph is serialized by the exact build that will later consume it. Unlike arcasHLA's image, this one is public (Biocontainers/Galaxy depot), so there is no companion image-build script: the container is pulled on first use. Docker is used when its daemon is reachable, otherwise Singularity/Apptainer.

Budget for it before starting:

- **~29 GB on disk** for the extracted and indexed graph (`serializedGRAPH` alone is ~5.5 GB), plus the 2.25 GB tarball. The script checks free space on the target filesystem up front (override the floor with `REQUIRED_GB`) rather than failing hours in.
- **A few hours**, and per HLA-LA's own README indexing "might take up to 40G of memory". The script warns if the machine has less than 40 GB of RAM but still proceeds.

Re-running the script is free: if `<output-dir>/<graph>/serializedGRAPH` already exists and is non-empty, it reports the graph as already built and exits without downloading, extracting, or indexing anything - that check runs _before_ the download. **To rebuild, delete the graph directory and re-run**; that is deliberately the only supported way, so there is no "force" flag that could half-overwrite an existing graph. An interrupted run that already extracted the package resumes at the indexing step instead of re-downloading. `GRAPH_NAME`, `GRAPH_URL`, `GRAPH_MD5`, `TARBALL` (use an already-downloaded copy), `IMAGE_TAG`, `SIF_PATH`, and `REQUIRED_GB` are all overridable - see `scripts/build_reference_hlala.sh --help`.

On success the script prints the exact parameters to pass:

```bash
--hlala_graph_dir /path/to/HLA-LA/graphs --hlala_graph PRG_MHC_GRCh38_withIMGT
```

**Limitation: the script fetches and indexes a _published_ graph; it cannot construct one from scratch.** This is not an unfinished feature - building a PRG graph for a newer IMGT/HLA release or for custom loci is not scriptable outside the tool author's own environment. HLA-LA's own `src/Update graphs.txt` documents that workflow as Perl scripts run on the author's Windows laptop, plus the separate older MHC-PRG v1 binary (not shipped in the bioconda `hla-la` package), hardcoded cluster paths, and input files that were never distributed. A newer graph is an upstream request to the HLA-LA authors. The `GRAPH_NAME`/`GRAPH_URL`/`GRAPH_MD5` overrides exist so other _published_ graph packages, an offline mirror, or a future move of the download host work without editing the script.

### Requirement: `--outdir` and the Nextflow work directory must share a filesystem

**When `--wgs_samples` is used, `--outdir` and the Nextflow work directory (`-w`, default `./work`) must be on the same filesystem.** This is a hard requirement, not a recommendation.

HLA-LA's per-sample output directory is published with `mode: 'link'` (hard links) rather than the pipeline's usual `copy` - see the `HLALA_TYPING` entry in `conf/modules.config`. The `HLALA_TYPING` module declares its per-sample output directory as an output alongside individual files inside it, which makes publishing all-or-nothing (Nextflow offers only the directory to `publishDir`, never the nested paths), and publishing everything by copy would duplicate HLA-LA's multi-gigabyte intermediates (`extraction*.bam`, `remapped_with_a.bam`, `R_{1,2,U}.fastq`) for every WGS sample. Hard links make that free.

Hard links cannot cross filesystems, and **Nextflow does not fall back to copying**: if `--outdir` is on a different filesystem than the work directory, the run aborts with

```
Failed to publish file: /path/to/work/xx/xxxxxx/<sample_id>; to: /path/to/outdir/hlala/<sample_id> [link]
```

This is easy to hit on HPC, where the normal layout is `--outdir` on shared/project storage and `-w` on fast local scratch. Either put both on the same filesystem, or override the publishing mode in a custom config passed with `-c`:

```groovy title="hlala_copy.config"
process {
    withName: 'HLALA_TYPING' {
        publishDir = [
            path: { "${params.outdir}/hlala" },
            mode: 'copy'
        ]
    }
}
```

Be aware that this reintroduces the multi-gigabyte-per-sample duplication that `'link'` exists to avoid. `'symlink'`/`'rellink'` are cheaper alternatives, but the published results then break as soon as the work directory is cleaned.

## SNP-array samplesheet input (HIBAG)

HIBAG is the alternative to HLA-LA for the genotype-side HLA calls. Instead of typing HLA from WGS alignments, it _imputes_ HLA alleles from GWAS SNP genotypes, so its input is microarray data in PLINK binary format:

```bash
--array_samples '[path to SNP-array samplesheet file]' --hibag_model '[path to a pre-fit HIBAG model .RData]'
```

**`--array_samples` and `--wgs_samples` are mutually exclusive.** Both fill the same genotype-side input to the consensus step, so the pipeline fails fast if given both rather than silently picking one.

The SNP-array samplesheet must be a comma-separated file with exactly these columns:

```csv title="array_samples.csv"
array_sample_id,array_bed_path,array_bim_path,array_fam_path
NA12878_omniexpress,testdata-make/hlarnases-testdata/array/NA12878.omniexpress.xMHC.hg19.bed,testdata-make/hlarnases-testdata/array/NA12878.omniexpress.xMHC.hg19.bim,testdata-make/hlarnases-testdata/array/NA12878.omniexpress.xMHC.hg19.fam
```

| Column            | Description                                                                               |
| ----------------- | ----------------------------------------------------------------------------------------- |
| `array_sample_id` | Label for the PLINK **dataset**. Mandatory, cannot contain spaces. See the warning below. |
| `array_bed_path`  | Path to the PLINK `.bed` genotype file. Mandatory, must end in `.bed`.                    |
| `array_bim_path`  | Path to the matching `.bim` variant file. Mandatory, must end in `.bim`.                  |
| `array_fam_path`  | Path to the matching `.fam` sample file. Mandatory, must end in `.fam`.                   |

Relative paths are resolved from the directory containing the samplesheet, the launch directory, or the pipeline project directory, as for the other samplesheets. An [example SNP-array samplesheet](../assets/array_samples.csv) is provided with the pipeline.

### :warning: A row is one PLINK dataset, not one sample

This is the one place where the SNP-array samplesheet behaves differently from the RNA and WGS ones. A PLINK fileset can hold many samples, and HIBAG imputes all of them in a single call, so:

- `array_sample_id` is only a **label** for the dataset. It is used for task tags and output filenames, and nothing else.
- The sample IDs that reach the consensus step come from the **IID column of the `.fam` file**.

It is therefore the `.fam` IIDs - not `array_sample_id` - that must match the `wgs_sample_id` values in `--sample_key`. If they do not match, the affected individuals simply produce no consensus rows rather than raising an error, so check this first if consensus output looks empty.

### The HIBAG model

`--hibag_model` is **mandatory** whenever `--array_samples` is given, and the pipeline fails fast if it is missing or does not exist.

The file must be an `.RData` holding either a single `hlaAttrBagObj` or a named list of them, one per HLA locus - the shape the published HIBAG per-platform models use. Pick a model built for your array platform and genome assembly; the pipeline never trains one. By default every locus in the model file is predicted; restrict that with `--hibag_loci 'A,B,C'`.

Set `--hibag_assembly` (`hg18`/`hg19`/`hg38`, default `hg19`) to the assembly of your **genotypes**, and make sure the model was built on the same one.

### :warning: If HIBAG reports that no SNPs match

The most common failure is a model whose SNP coordinates do not line up with your array manifest. HIBAG's own error for this is a bare `There is no overlapping of SNPs!`, so the pipeline checks the overlap first and fails with something you can act on:

```text
HLA-A: none of the model's 266 SNPs match the array data under --match-type 'RefSNP+Position'.
    SNPs found under each criterion:
      Position         0 of 266 model SNPs
      Pos+Allele       0 of 266 model SNPs
      RefSNP+Position  0 of 266 model SNPs
      RefSNP           264 of 266 model SNPs
    Try --match-type with one of: RefSNP.
```

Set `--hibag_match_type` to whichever criterion the message says will work. The default is the strict `RefSNP+Position`, which is correct when the model and the genotypes were built against the same manifest and assembly. `RefSNP` matches on rsID alone and is the usual fix for a coordinate offset. If _no_ criterion matches anything, the model and the data are on different assemblies, or the array does not cover the xMHC.

`--hibag_min_prob` (default `0`, i.e. no filtering) drops calls whose posterior probability falls below the threshold. The default matches the HLA-LA path, which applies no confidence filter either.

### :warning: Partial SNP overlap is rejected, not warned about

HIBAG does **not** fail when only some of a model's SNPs are found. It returns confident-looking alleles computed from whatever matched, and they can simply be wrong. Observed against a published model whose rsIDs had gone stale: at 13 of 273 matched SNPs it reported a homozygous `C*07:01`/`C*07:01`, where the same data and model at 271 of 273 gave the correct `C*01:02`/`C*07:01`.

`--hibag_min_matched_snps` (default `0.5`) therefore fails the run when fewer than that fraction of a locus's model SNPs are found, with the same diagnostic table as the zero-overlap error. The per-locus matched fraction is logged for every run and recorded in `<array_sample_id>.hibag_posterior.tsv` as `n_model_snps` / `n_matched_snps`.

Set it to `0` to disable the check, only if you accept unreliable calls.

### Getting a multi-locus model

The model bundled with the HIBAG R package covers **HLA-A only**, so a run using it reports one locus. For the test data, `testdata-make/11-download-hibag-model` fetches a published model covering A, B, C, DRB1, DQA1, DQB1 and DPB1:

```bash
testdata-make/11-download-hibag-model
```

These are the "HLARES" parameter estimates of Zheng et al. (2014), built from SNP markers common to the Illumina 1M Duo, OmniQuad, OmniExpress, 660K and 550K platforms. Four ancestries are published (`HIBAG_ANCESTRY`: European, Asian, Hispanic, African) in hg18 and hg19 (`HIBAG_MODEL_ASSEMBLY`); European/hg19 is the default and is the right one for NA12878.

They carry accurate hg19 positions but 2012-era rsIDs, many of which have since been merged or retired, so they need `--hibag_match_type Pos+Allele` — rsID matching finds only a few percent of each model's SNPs. `pipeline_testdata_run.sh` sets this for you.

### HIBAG dependency

`HIBAG_PREDICT` follows the standard nf-core pattern: its dependency is declared once in [`modules/local/hibag/predict/environment.yml`](../modules/local/hibag/predict/environment.yml) (`bioconda::bioconductor-hibag=1.42.0`), which feeds both the module's `conda` directive and a matching pinned Biocontainers/Galaxy-depot `container` directive. Run the SNP-array path with one of `-profile conda`, `-profile docker`, `-profile singularity` or `-profile apptainer` and Nextflow provisions HIBAG for you.

The package is deliberately **not** listed in [`envs/nf-core.yml`](../envs/nf-core.yml), so nothing here depends on `HIBAG` being installed in the environment you launch Nextflow from. Running with none of those profiles fails at this step with an explicit message naming the profiles to use, rather than silently imputing with whatever version happens to be on the host.

The pin is 1.42.0 rather than the newer 1.46.0 because 1.42.0 is the most recent release for which the Galaxy depot publishes a Singularity image, so a single version covers all four profiles.

### Preparing SNP-array test data

`testdata-make/10-prepare-na12878-array-hibag` downloads the NA12878 / GM12878 Illumina HumanOmniExpress-24 v1.0 array data from GEO and converts it to the PLINK genotypes this step consumes. See [`testdata-make/README.md`](../testdata-make/README.md) for what the conversion does and its limitations.

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

| Column             | Description                                                               |
| ------------------ | ------------------------------------------------------------------------- |
| `rnaseq_sample_id` | RNA sample identifier; must match a `rna_id` from `--rna_samples`.        |
| `wgs_sample_id`    | WGS sample identifier; must match a `WGS_sample_id` from `--wgs_samples`. |

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

Building the personalized reference is invoked inside a dedicated Conda environment named `hlapm`, separate from the pipeline's main runtime environment. This environment is an **operator-prepared precondition**, worded like the HLA-LA section above: the pipeline does not create it, install packages into it, or update the HLApm checkout at any point. Before running the pipeline with `--rna_samples` (and therefore `--sample_key`), prepare this environment yourself with:

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

Per-allele-level read counts, a cross-sample combined gene-count table, and comparison against `featureCounts` ground truth remain out of scope for this iteration.

#### `hlapm-quantify` Conda environment

Running `make_a_table_210804_allHLAgenes.py` and `summarize_hla_readcounts.R` are both invoked inside a dedicated Conda environment named `hlapm-quantify`, separate from the pipeline's main runtime environment. This environment is an **operator-prepared precondition**, worded like the `hlapm`/HLA-LA sections above: the pipeline does not create it or install packages into it at any point. Before running the pipeline with `--rna_samples` (and therefore `--sample_key`), prepare this environment yourself with:

- Python 2
- `pybam` (`pip install https://github.com/JohnLonginotto/pybam/zipball/master`)
- `intervaltree` (PyPI)
- R (>= 4.0, matching the `hlapm` env's floor)
- CRAN packages `dplyr`, `tidyr`

For example:

```bash
mamba install -n hlapm-quantify -c conda-forge r-base r-dplyr r-tidyr
```

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run nf-core/hlarnaseq \
    --rna_samples ./rna_samples.csv \
    --hla_region chr6:28500000-33400000 \
    --outdir ./results
```

This early-stage pipeline expects samtools to be available in the active Conda environment; read-pair validation and arcasHLA genotyping provision their own tool environment/container automatically, as described above.

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
