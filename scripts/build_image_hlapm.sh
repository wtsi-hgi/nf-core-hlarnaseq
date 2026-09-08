#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/build_image_hlapm.sh

Builds the HLAPM_BUILD_REF container image(s) locally for
modules/local/hlapm/build_ref, so its `container` directive resolves with no
registry push required:

  - Docker: builds and tags the image as IMAGE_TAG (default
    quay.io/hlarnaseq/hlapm-build-ref:38faa60 - matching nextflow.config's
    docker.registry, so Docker finds it locally under -profile docker without
    ever attempting a network pull).
  - Singularity/Apptainer: if `singularity` or `apptainer` is also available,
    additionally converts that same local Docker image straight from the
    Docker daemon (docker-daemon://) into a .sif file at SIF_PATH (default
    modules/local/hlapm/build_ref/hlapm-build-ref.sif). The module's
    `container` directive references this .sif by path under -profile
    singularity/apptainer - Nextflow uses a local file directly, no pull
    attempted, no registry involved at all. This is the piece that actually
    matters for an HPC + Singularity deployment: Singularity has no access to
    Docker's local image store on its own, and a bare image name (even one
    retagged to match docker.registry/singularity.registry) is not a
    filesystem path, so without this .sif Nextflow would still try (and fail)
    to pull it from quay.io over the network.

Unlike the arcasHLA image next door, this one bakes in the tool's own
repository: HLApm is an unpackaged git repo (no Conda package), cloned at the
pinned commit HLAPM_COMMIT during the build. The build therefore needs network
access to github.com as well as to the Conda channels. With this image built,
--hlapm_repo is optional under a container profile; it remains required under
-profile conda, which can install the R stack but not a git checkout.

Environment:
  IMAGE_TAG      Docker image reference to build/tag. Default: quay.io/hlarnaseq/hlapm-build-ref:38faa60
  SIF_PATH       Output path for the converted Singularity image. Default: modules/local/hlapm/build_ref/hlapm-build-ref.sif
  HLAPM_COMMIT   HLApm commit to bake in. Default: the Dockerfile's own pin
                 (38faa6087bbd827ccab969d947f8df101e95d688). If you override
                 it, override IMAGE_TAG too so the tag keeps naming what is
                 actually inside the image.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="${ROOT_DIR}/modules/local/hlapm/build_ref"
IMAGE_TAG="${IMAGE_TAG:-quay.io/hlarnaseq/hlapm-build-ref:38faa60}"
SIF_PATH="${SIF_PATH:-${MODULE_DIR}/hlapm-build-ref.sif}"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: docker is required to build this image" >&2
    exit 127
}

BUILD_ARGS=()
if [[ -n "${HLAPM_COMMIT:-}" ]]; then
    BUILD_ARGS+=(--build-arg "HLAPM_COMMIT=${HLAPM_COMMIT}")
    echo "Using HLApm commit ${HLAPM_COMMIT} (overriding the Dockerfile default)."
fi

echo "Building ${IMAGE_TAG} from ${MODULE_DIR} ..."
# --no-cache: this image gets rebuilt repeatedly while iterating on
# environment.yml/Dockerfile, and a stale cached layer silently surviving a
# real change is a much more confusing failure mode than a slower rebuild.
# It also keeps the HLApm clone honest - a cached clone layer would otherwise
# survive an HLAPM_COMMIT change made through the Dockerfile default.
docker build --no-cache "${BUILD_ARGS[@]}" -t "${IMAGE_TAG}" "${MODULE_DIR}"
echo "Built ${IMAGE_TAG} (HLApm $(docker run --rm "${IMAGE_TAG}" cat /opt/HLApm/HLApm.version))."

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
    echo "      -profile singularity/apptainer will not work for HLAPM_BUILD_REF until this is built." >&2
fi
