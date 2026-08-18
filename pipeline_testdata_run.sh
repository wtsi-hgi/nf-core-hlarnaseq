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
OUTDIR="${OUTDIR:-${RUN_DIR}/results}"
NEXTFLOW_WORKDIR="${NEXTFLOW_WORKDIR:-${RUN_DIR}/nextflow.workdir}"
NEXTFLOW_LOG="${NEXTFLOW_LOG:-${RUN_DIR}/testdata.log}"
RNA_SAMPLESHEET="${RNA_SAMPLESHEET:-${ROOT_DIR}/assets/rna_samples.csv}"
WGS_SAMPLESHEET="${WGS_SAMPLESHEET:-${ROOT_DIR}/assets/wgs_samples.csv}"
RNA_WGS_KEY="${RNA_WGS_KEY:-${ROOT_DIR}/assets/rna_wgs_key.csv}"
HLALA_GRAPHS="${ROOT_DIR}/testdata-make/hlarnases-testdata/hla-la_graphs"
PROFILE="${PROFILE:-}"
HLA_REGION="${HLA_REGION:-chr6:28500000-33400000}"
HLAPM_DIR="${RUN_DIR}/HLApm/"
GTF="${ROOT_DIR}/testdata-make/hlarnases-testdata/reference/gencode.v50.primary_assembly.annotation.gtf.gz"

mkdir -p "${RUN_DIR}"

cd "${ROOT_DIR}"
echo "Running nf-core/hlarnaseq testdata"
echo "Profile: ${PROFILE:-<none>}"
echo "Run dir: ${RUN_DIR}"
echo "Outdir: ${OUTDIR}"
echo "Work dir: ${NEXTFLOW_WORKDIR}"
echo "Log: ${NEXTFLOW_LOG}"
echo "RNA_SAMPLESHEET: $RNA_SAMPLESHEET"

if [ ! -d "$HLAPM_DIR" ]; then
    git clone https://github.com/davenportlab/HLApm.git "$HLAPM_DIR"
fi

nextflow -log "${NEXTFLOW_LOG}" \
    run . \
    -work-dir "${NEXTFLOW_WORKDIR}" \
    -profile singularity \
    -resume \
    --gtf "$GTF" \
    --rna_samples "${RNA_SAMPLESHEET}" \
    --hla_region "${HLA_REGION}" \
    --wgs_samples "${WGS_SAMPLESHEET}" \
    --hlala_graph_dir "$HLALA_GRAPHS"  \
    --sample_key "$RNA_WGS_KEY" \
    --hlapm_repo "$HLAPM_DIR" \
    --outdir "${OUTDIR}" \
    "$@"

# The HLA-LA run takes a long to complete, so for test runs you can remove the following options
# --wgs_samples "${WGS_SAMPLESHEET}" \
# --hlala_graph_dir "$HLALA_GRAPHS"  \
