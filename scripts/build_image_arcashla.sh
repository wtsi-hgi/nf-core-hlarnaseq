#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/build_image_arcashla.sh

Builds the ARCASHLA_GENOTYPE container image(s) locally for
modules/local/arcashla/genotype, so its `container` directive resolves with
no registry push required:

  - Docker: builds and tags the image as IMAGE_TAG (default
    quay.io/hlarnaseq/arcashla-genotype:0.6.0 - matching nextflow.config's
    docker.registry, so Docker finds it locally under -profile docker
    without ever attempting a network pull).
  - Singularity/Apptainer: if `singularity` or `apptainer` is also
    available, additionally converts that same local Docker image straight
    from the Docker daemon (docker-daemon://) into a .sif file at SIF_PATH
    (default modules/local/arcashla/genotype/arcashla-genotype.sif). The
    module's `container` directive references this .sif by path under
    -profile singularity/apptainer - Nextflow uses a local file directly, no
    pull attempted, no registry involved at all. This is the piece that
    actually matters for an HPC + Singularity deployment: Singularity has no
    access to Docker's local image store on its own, and a bare image name
    (even one retagged to match docker.registry/singularity.registry) is
    not a filesystem path, so without this .sif Nextflow would still try
    (and fail) to pull it from quay.io over the network.

Environment:
  IMAGE_TAG   Docker image reference to build/tag. Default: quay.io/hlarnaseq/arcashla-genotype:0.6.0
  SIF_PATH    Output path for the converted Singularity image. Default: modules/local/arcashla/genotype/arcashla-genotype.sif
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="${ROOT_DIR}/modules/local/arcashla/genotype"
IMAGE_TAG="${IMAGE_TAG:-quay.io/hlarnaseq/arcashla-genotype:0.6.0}"
SIF_PATH="${SIF_PATH:-${MODULE_DIR}/arcashla-genotype.sif}"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: docker is required to build this image" >&2
    exit 127
}

echo "Building ${IMAGE_TAG} from ${MODULE_DIR} ..."
docker build -t "${IMAGE_TAG}" "${MODULE_DIR}"
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
    echo "      -profile singularity/apptainer will not work for ARCASHLA_GENOTYPE until this is built." >&2
fi
