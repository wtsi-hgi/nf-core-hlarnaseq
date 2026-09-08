#!/bin/sh

SCRIPT_DIR="${TESTDATA_MAKE_DIR:-$(pwd)}"
DATA_DIR="${SCRIPT_DIR}/data"
FINAL_TESTDATA_DIR="${FINAL_TESTDATA_DIR:-${SCRIPT_DIR}/hlarnases-testdata}"

REFERENCE_DIR="${FINAL_TESTDATA_DIR}/reference"
WGS_DIR="${DATA_DIR}/wgs"
HLA_DIR="${FINAL_TESTDATA_DIR}/wgs"

GENCODE_RELEASE="${GENCODE_RELEASE:-50}"
GENCODE_BASE_URL="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_${GENCODE_RELEASE}"
GENCODE_FASTA_GZ_NAME="GRCh38.primary_assembly.genome.fa.gz"
GENCODE_GTF_GZ_NAME="gencode.v${GENCODE_RELEASE}.primary_assembly.annotation.gtf.gz"
GENCODE_FASTA_GZ="${REFERENCE_DIR}/${GENCODE_FASTA_GZ_NAME}"
GENCODE_GTF_GZ="${REFERENCE_DIR}/${GENCODE_GTF_GZ_NAME}"
GENCODE_REFERENCE_FASTA="${REFERENCE_DIR}/${GENCODE_FASTA_GZ_NAME%.gz}"
GENCODE_REFERENCE_FAI="${GENCODE_REFERENCE_FASTA}.fai"

NA12878_BASE_URL="ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR323/ERR3239334"
NA12878_CRAM_NAME="NA12878.final.cram"
NA12878_CRAI_NAME="${NA12878_CRAM_NAME}.crai"
NA12878_CRAM="${WGS_DIR}/${NA12878_CRAM_NAME}"
NA12878_CRAI="${WGS_DIR}/${NA12878_CRAI_NAME}"

# HLA_REGION="${HLA_REGION:-chr6:28510120-33480577}" # Full-sized HLA region.
HLA_REGION="${HLA_REGION:-chr6:29840000-31470000}" # covers only HLA-A, HLA-C, HLA-B plus padding
THREADS="${THREADS:-2}"

HLA_BAM="${HLA_DIR}/NA12878.chr6_hla.GRCh38.bam"
HLA_BAI="${HLA_BAM}.bai"
HLA_TMP_BAM="${HLA_BAM}.tmp"

# NA12878 / GM12878 Illumina HumanOmniExpress-24 v1.0 SNP array (GSE96790).
# Used to produce PLINK BED/BIM/FAM genotypes for HIBAG HLA imputation.
ARRAY_DIR="${DATA_DIR}/array"
ARRAY_IDAT_DIR="${ARRAY_DIR}/idat"
ARRAY_FINAL_REPORT_DIR="${ARRAY_DIR}/final_report"
ARRAY_MANIFEST="${ARRAY_DIR}/manifest.tsv"
ARRAY_HIBAG_DIR="${FINAL_TESTDATA_DIR}/array"

ARRAY_GEO_BASE_URL="https://ftp.ncbi.nlm.nih.gov/geo/samples"
ARRAY_PLATFORM="IlluminaHumanOmniExpress-24v1-0"
ARRAY_REPORT_PLATFORM="HumanOmniExpress-24v1-0"

# Array positions are GRCh37/hg19, matching the published HIBAG pre-fit models.
# The default region is a deliberate superset of HIBAG's own xMHC import window
# so that HIBAG stays the authority on the exact boundary. Use "all" to keep
# every SNP.
ARRAY_REGION="${ARRAY_REGION:-6:25000000-34000000}"
ARRAY_SAMPLE_ID="${ARRAY_SAMPLE_ID:-NA12878}"
ARRAY_PLINK_PREFIX="${ARRAY_HIBAG_DIR}/${ARRAY_SAMPLE_ID}.omniexpress.xMHC.hg19"

# GSM2544146 is the second technical replicate; the IDATs cannot be genotyped
# without a licensed BPM/EGT manifest and are downloaded for provenance only.
INCLUDE_REPLICATE="${INCLUDE_REPLICATE:-0}"
INCLUDE_IDAT="${INCLUDE_IDAT:-1}"

# Published HIBAG pre-fit models ("HLARES" parameter estimates, Zheng et al.
# 2014), built from SNPs common to the Illumina 1M Duo, OmniQuad, OmniExpress,
# 660K and 550K platforms - which is why they suit the OmniExpress test data.
# Four ancestries x two assemblies are published; NA12878 is CEU, so European
# on hg19 is the default.
HIBAG_MODEL_BASE_URL="https://hibag.s3.amazonaws.com/download/hlares_param"
HIBAG_ANCESTRY="${HIBAG_ANCESTRY:-European}"
HIBAG_MODEL_ASSEMBLY="${HIBAG_MODEL_ASSEMBLY:-hg19}"
HIBAG_MODEL_NAME="${HIBAG_ANCESTRY}-HLA4-${HIBAG_MODEL_ASSEMBLY}.RData"
HIBAG_MODEL="${HIBAG_MODEL:-${ARRAY_HIBAG_DIR}/${HIBAG_MODEL_NAME}}"

# Observed md5 of European-HLA4-hg19.RData on 2026-08-28. Upstream publishes no
# digest for these files, so this is a change-detector, not an authenticity
# check, and a mismatch is a warning rather than an error - see
# 11-download-hibag-model.
HIBAG_MODEL_KNOWN_MD5_European_hg19="c6be4cf97794fef7e3bb571f99cda855"

RNA_DIR="${DATA_DIR}/rna"
RNA_DOWNLOAD_DIR="${DATA_DIR}/gm12878_rnaseq_fastq"
RNA_FASTQ_ROOT="${RNA_DOWNLOAD_DIR}/fastq"
RNASEQ_SAMPLESHEET="${RNA_DIR}/rnaseq_samplesheet.csv"
RNASEQ_OUTDIR="${RNA_DIR}/nf-core-rnaseq"
RNASEQ_WORKDIR="${RNA_DIR}/nf-core-rnaseq.workdir"
RNA_HLARNASEQ_DIR="${FINAL_TESTDATA_DIR}/rnaseq"
RNA_HLARNASEQ_MANIFEST="${RNA_HLARNASEQ_DIR}/rna_samples.csv"
RNA_HLA_BAM_DIR="${RNA_HLARNASEQ_DIR}/hla_bam"
RNA_UNMAPPED_FASTQ_DIR="${RNA_HLARNASEQ_DIR}/unmapped_fastq"
RNA_GENE_COUNTS_DIR="${RNA_HLARNASEQ_DIR}/gene_counts"
