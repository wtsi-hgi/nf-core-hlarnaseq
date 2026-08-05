#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  pipeline_testdata_run.sh [nextflow arguments...]

Runs the local nf-core/hlarnaseq testdata through Nextflow.

Environment:
  PROFILE            Optional Nextflow profile to use. Default: unset
  RUN_DIR            Directory for generated inputs, logs, work, and default results.
                     Default: <repo>/artifacts/testdata-run
  OUTDIR             Nextflow --outdir. Default: <RUN_DIR>/results
  NEXTFLOW_WORKDIR   Nextflow work directory. Default: <RUN_DIR>/nextflow.workdir
  NEXTFLOW_LOG       Nextflow log path. Default: <RUN_DIR>/testdata.log
  WGS_SAMPLESHEET    WGS samplesheet path. Default: <repo>/assets/wgs_samples.csv
  HLA_REGION         Region passed unchanged to samtools. Default: chr6:28500000-33400000
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${RUN_DIR:-${ROOT_DIR}/artifacts/testdata-run}"
RNA_SAMPLESHEET="${RUN_DIR}/rna_samples.csv"
OUTDIR="${OUTDIR:-${RUN_DIR}/results}"
NEXTFLOW_WORKDIR="${NEXTFLOW_WORKDIR:-${RUN_DIR}/nextflow.workdir}"
NEXTFLOW_LOG="${NEXTFLOW_LOG:-${RUN_DIR}/testdata.log}"
WGS_SAMPLESHEET="${WGS_SAMPLESHEET:-${ROOT_DIR}/assets/wgs_samples.csv}"
RNA_WGS_KEY="${RNA_WGS_KEY:-${ROOT_DIR}/assets/rna_wgs_key.csv}"
HLALA_GRAPHS="${ROOT_DIR}/testdata-make/hlarnases-testdata/hla-la_graphs"
PROFILE="${PROFILE:-}"
HLA_REGION="${HLA_REGION:-chr6:28500000-33400000}"
HLAPM_DIR="${RUN_DIR}/HLApm/"

mkdir -p "${RUN_DIR}"

cat > "${RNA_SAMPLESHEET}" <<CSV
rna_id,bam,bai,unpaired_r1,unpaired_r2
SRR3192657_GSM2072350_ENCLB038ZZZ,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/hla_bam/SRR3192657_GSM2072350_ENCLB038ZZZ.chr6_hla.GRCh38.bam,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/hla_bam/SRR3192657_GSM2072350_ENCLB038ZZZ.chr6_hla.GRCh38.bam.bai,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/unmapped_fastq/SRR3192657_GSM2072350_ENCLB038ZZZ.unmapped_1.fastq.gz,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/unmapped_fastq/SRR3192657_GSM2072350_ENCLB038ZZZ.unmapped_2.fastq.gz
CSV

cd "${ROOT_DIR}"

echo "Running nf-core/hlarnaseq testdata"
echo "Profile: ${PROFILE:-<none>}"
echo "Run dir: ${RUN_DIR}"
echo "Outdir: ${OUTDIR}"
echo "Work dir: ${NEXTFLOW_WORKDIR}"
echo "Log: ${NEXTFLOW_LOG}"

profile_args=()
if [[ -n "${PROFILE}" ]]; then
    profile_args=(-profile "${PROFILE}")
fi

nextflow -log "${NEXTFLOW_LOG}" \
    run . \
    "${profile_args[@]}" \
    -work-dir "${NEXTFLOW_WORKDIR}" \
    -resume \
    --rna_samples "${RNA_SAMPLESHEET}" \
    --hla_region "${HLA_REGION}" \
    --wgs_samples "${WGS_SAMPLESHEET}" \
    --hlala_graph_dir "$HLALA_GRAPHS"  \
    --sample_key "$RNA_WGS_KEY" \
    --hlapm_repo "$HLAPM_DIR" \
    --outdir "${OUTDIR}" \
    "$@"
