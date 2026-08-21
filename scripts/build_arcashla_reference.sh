#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/build_arcashla_reference.sh <output-dir>

Builds the arcasHLA IMGT/HLA + kallisto reference once, into <output-dir>,
by running it inside the same container image scripts/build_image_arcashla.sh
builds for ARCASHLA_GENOTYPE - so the reference is produced with the exact
pinned arcas-hla/kallisto versions the pipeline itself runs, with no
separate Conda environment to set up.

This does NOT just run `arcasHLA reference` as-is. Plain `arcasHLA
reference` clones the CURRENT github.com/ANHIG/IMGTHLA default branch, but
as of that project's Release 3.56.0 (April 2024) its large files - including
hla.dat, which arcasHLA 0.6.0 expects as a plain file - are distributed as
separate .zip downloads instead of being checked into git, so a plain clone
of the current repository state no longer works with this pinned arcasHLA
version at all (it fails with a confusing FileNotFoundError, not a clear
error). Instead, this script clones IMGTHLA itself and checks out a pinned
historical commit - IMGT/HLA version 3.46.0, the newest version arcasHLA
0.6.0 itself has a built-in commit mapping for (see IMGTHLA_COMMIT below) -
which predates that restructuring, then runs `arcasHLA reference --rebuild`
against it (skipping arcasHLA's own now-broken fetch logic entirely). This
also has the side benefit of pinning the exact HLA database version for
reproducibility, rather than depending on whatever the upstream default
branch happens to contain when this script is run.

Run scripts/build_image_arcashla.sh first if you haven't already - this
script needs at least one of the images it builds to already exist.

Point the pipeline at the result with:
  --arcashla_reference_dir <output-dir>

Environment:
  IMAGE_TAG        Docker image to run, if present. Default: quay.io/hlarnaseq/arcashla-genotype:0.6.0
  SIF_PATH         Singularity image to run instead, if IMAGE_TAG isn't loaded in Docker. Default: modules/local/arcashla/genotype/arcashla-genotype.sif
  IMGTHLA_COMMIT   IMGT/HLA commit to check out. Default: 8d77b3dd93959663d58ae5b626289d0746edd0e7 (version 3.46.0)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-quay.io/hlarnaseq/arcashla-genotype:0.6.0}"
SIF_PATH="${SIF_PATH:-${ROOT_DIR}/modules/local/arcashla/genotype/arcashla-genotype.sif}"
IMGTHLA_COMMIT="${IMGTHLA_COMMIT:-8d77b3dd93959663d58ae5b626289d0746edd0e7}"

mkdir -p "$1"
OUTPUT_DIR="$(cd "$1" && pwd)"

# The reference-build command run inside the container: locate this
# arcasHLA install's own share/dat directory (same discovery main.nf uses),
# clone IMGTHLA and pin it to IMGTHLA_COMMIT ourselves (see usage() above
# for why), run arcasHLA reference --rebuild against that pinned checkout,
# then copy just dat/ref (the kallisto index + processed sequences genotype
# reads - not the ~4GB raw IMGT/HLA git checkout under dat/IMGTHLA, which
# only exists to build dat/ref) to a fixed, container-internal path. This is
# deliberately NOT the bind-mounted output directory itself: the
# mambaorg/micromamba base image runs as a non-root user by default, which
# generally cannot write into a bind-mounted host directory it doesn't own
# (this pipeline's own nextflow.config docker profile works around the same
# class of problem for its own container runs, via `docker.runOptions = '-u
# $(id -u):$(id -g)'` - but forcing that here risks breaking the *earlier*
# steps above instead, if the invoking host user's UID happens not to match
# whatever UID this image's /opt/conda is actually owned by).
REF_OUT=/tmp/arcashla-reference-out
BUILD_CMD="
set -euo pipefail
ARCASHLA_PREFIX=\"\$(cd \"\$(dirname \"\$(command -v arcasHLA)\")/..\" && pwd)\"
ARCASHLA_HOME=\"\$(find \"\${ARCASHLA_PREFIX}/share\" -maxdepth 1 -iname 'arcas-hla-*' -type d | head -n1)\"
IMGTHLA_DIR=\"\${ARCASHLA_HOME}/dat/IMGTHLA\"

echo \"Cloning IMGT/HLA and checking out ${IMGTHLA_COMMIT} ...\"
rm -rf \"\${IMGTHLA_DIR}\"
git clone https://github.com/ANHIG/IMGTHLA.git \"\${IMGTHLA_DIR}\"
git -C \"\${IMGTHLA_DIR}\" checkout -f '${IMGTHLA_COMMIT}'
git -C \"\${IMGTHLA_DIR}\" lfs install --local
git -C \"\${IMGTHLA_DIR}\" lfs pull

if [[ ! -s \"\${IMGTHLA_DIR}/hla.dat\" ]] || head -c 200 \"\${IMGTHLA_DIR}/hla.dat\" | grep -q 'git-lfs.github.com'; then
    echo 'ERROR: hla.dat is missing or still a git-lfs pointer after git lfs pull.' >&2
    exit 1
fi

echo \"Building arcasHLA reference under \${ARCASHLA_HOME} from the pinned IMGT/HLA checkout ...\"
arcasHLA reference --rebuild -v
mkdir -p '${REF_OUT}'
cp -a \"\${ARCASHLA_HOME}/dat/ref/.\" '${REF_OUT}/'
"

if command -v docker >/dev/null 2>&1 && docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
    echo "Running arcasHLA reference via Docker image ${IMAGE_TAG} ..."
    # docker cp (run as whoever invoked this script, on the host side) writes
    # the result to OUTPUT_DIR - unlike a bind mount, this never touches the
    # container's own (possibly restricted) view of the host filesystem, so
    # it works regardless of which UID the image happens to run as.
    CONTAINER_ID="$(docker create "${IMAGE_TAG}" bash -c "${BUILD_CMD}")"
    trap 'docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true' EXIT
    docker start -a "${CONTAINER_ID}"
    docker cp "${CONTAINER_ID}:${REF_OUT}/." "${OUTPUT_DIR}"
    docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
    trap - EXIT
elif [[ -f "${SIF_PATH}" ]] && (command -v singularity >/dev/null 2>&1 || command -v apptainer >/dev/null 2>&1); then
    SIF_RUNNER="singularity"
    command -v singularity >/dev/null 2>&1 || SIF_RUNNER="apptainer"
    # Singularity/Apptainer run as the invoking host user by default (no
    # separate container user the way Docker images can have), so a plain
    # bind mount doesn't hit the permission problem docker cp works around
    # above.
    echo "Running arcasHLA reference via ${SIF_RUNNER} image ${SIF_PATH} ..."
    "${SIF_RUNNER}" exec --bind "${OUTPUT_DIR}:${REF_OUT}" "${SIF_PATH}" bash -c "${BUILD_CMD}"
else
    echo "ERROR: neither a loaded Docker image (${IMAGE_TAG}) nor a built Singularity/Apptainer image (${SIF_PATH}) was found." >&2
    echo "       Run scripts/build_image_arcashla.sh first." >&2
    exit 1
fi

if [[ ! -s "${OUTPUT_DIR}/hla.idx" ]]; then
    echo "ERROR: ${OUTPUT_DIR}/hla.idx is missing or empty after the build - check the output above for the actual failure and re-run." >&2
    exit 1
fi

echo
echo "Built arcasHLA reference (IMGT/HLA ${IMGTHLA_COMMIT}) at ${OUTPUT_DIR}."
echo "Use it with: --arcashla_reference_dir ${OUTPUT_DIR}"
