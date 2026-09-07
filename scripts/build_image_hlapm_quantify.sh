#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/build_image_hlapm_quantify.sh

Builds the HLAPM_QUANTIFY_READS container image(s) locally for
modules/local/hlapm/quantify_reads, so its `container` directive resolves with
no registry push required:

  - Docker: builds and tags the image as IMAGE_TAG (default
    quay.io/hlarnaseq/hlapm-quantify-reads:py2.7.15 - matching nextflow.config's
    docker.registry, so Docker finds it locally under -profile docker without
    ever attempting a network pull).
  - Singularity/Apptainer: if `singularity` or `apptainer` is also available,
    additionally converts that same local Docker image straight from the
    Docker daemon (docker-daemon://) into a .sif file at SIF_PATH (default
    modules/local/hlapm/quantify_reads/hlapm-quantify-reads.sif). The module's
    `container` directive references this .sif by path under -profile
    singularity/apptainer - Nextflow uses a local file directly, no pull
    attempted, no registry involved at all. Singularity has no access to
    Docker's local image store on its own, and a bare image name is not a
    filesystem path, so without this .sif Nextflow would still try (and fail)
    to pull it from quay.io over the network.

The image carries the legacy Python 2.7 stack for
bin/make_a_table_210804_allHLAgenes.py: python 2.7.15 (the newest Python 2
conda-forge ships - long EOL, deliberately frozen here), intervaltree 3.1.0,
and pybam pinned by commit. The build needs network access to the Conda
channels, PyPI and github.com.

Environment:
  IMAGE_TAG      Docker image reference to build/tag. Default: quay.io/hlarnaseq/hlapm-quantify-reads:py2.7.15
  SIF_PATH       Output path for the converted Singularity image. Default: modules/local/hlapm/quantify_reads/hlapm-quantify-reads.sif
  PYBAM_COMMIT   pybam commit to install. Default: the Dockerfile's own pin
                 (846d98603905c57c31bf7b9abaf2eb8c89899e60), which matches
                 environment.yml. If you override it, note that -profile conda
                 still uses environment.yml's URL - change both to keep the
                 Conda and container paths on the same pybam.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="${ROOT_DIR}/modules/local/hlapm/quantify_reads"
IMAGE_TAG="${IMAGE_TAG:-quay.io/hlarnaseq/hlapm-quantify-reads:py2.7.15}"
SIF_PATH="${SIF_PATH:-${MODULE_DIR}/hlapm-quantify-reads.sif}"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: docker is required to build this image" >&2
    exit 127
}

BUILD_ARGS=()
if [[ -n "${PYBAM_COMMIT:-}" ]]; then
    BUILD_ARGS+=(--build-arg "PYBAM_COMMIT=${PYBAM_COMMIT}")
    echo "Using pybam commit ${PYBAM_COMMIT} (overriding the Dockerfile default)."
    echo "NOTE: environment.yml still pins the default commit for -profile conda." >&2
fi

echo "Building ${IMAGE_TAG} from ${MODULE_DIR} ..."
# --no-cache: this image gets rebuilt repeatedly while iterating on
# environment.yml/Dockerfile, and a stale cached layer silently surviving a
# real change is a much more confusing failure mode than a slower rebuild.
docker build --no-cache "${BUILD_ARGS[@]}" -t "${IMAGE_TAG}" "${MODULE_DIR}"
echo "Built ${IMAGE_TAG}."

SIF_BUILDER=""
if command -v singularity >/dev/null 2>&1; then
    SIF_BUILDER="singularity"
elif command -v apptainer >/dev/null 2>&1; then
    SIF_BUILDER="apptainer"
fi

if [[ -n "${SIF_BUILDER}" ]]; then
    echo "Converting ${IMAGE_TAG} to ${SIF_PATH} with ${SIF_BUILDER} (from the local Docker daemon, no registry involved) ..."
    "${SIF_BUILDER}" build --force "${SIF_PATH}" "docker-daemon://${IMAGE_TAG}"
    echo "Built ${SIF_PATH}."
else
    echo "NOTE: neither singularity nor apptainer found on PATH - skipped building ${SIF_PATH}." >&2
    echo "      -profile singularity/apptainer will not work for HLAPM_QUANTIFY_READS until this is built." >&2
fi
