#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${ROOT_DIR}/artifacts/testdata-run"
INPUT_SAMPLESHEET="${RUN_DIR}/input.csv"
OUTDIR="${OUTDIR:-${RUN_DIR}/results}"
NEXTFLOW_WORKDIR="${RUN_DIR}/nextflow.workdir"
WGS_SAMPLESHEET="${WGS_SAMPLESHEET:-${ROOT_DIR}/assets/wgs_samples.csv}"

mkdir -p "${RUN_DIR}"

cat > "${INPUT_SAMPLESHEET}" <<CSV
sample,fastq_1,fastq_2
RNA_VALIDATION,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/unmapped_fastq/SRR3192657_GSM2072350_ENCLB038ZZZ.unmapped_1.fastq.gz,${ROOT_DIR}/testdata-make/hlarnases-testdata/rnaseq/unmapped_fastq/SRR3192657_GSM2072350_ENCLB038ZZZ.unmapped_2.fastq.gz
CSV

cd "${ROOT_DIR}"

nextflow -log "${RUN_DIR}/testdata.log" \
     run . \
    -profile singularity \
    -work-dir "${NEXTFLOW_WORKDIR}" \
    --input "${INPUT_SAMPLESHEET}" \
    --wgs_samples "${WGS_SAMPLESHEET}" \
    --outdir "${OUTDIR}" \
    "$@"
