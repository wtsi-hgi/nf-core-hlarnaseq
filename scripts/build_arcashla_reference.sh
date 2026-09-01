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

Disk space: the build clones the whole IMGT/HLA database (~4 GB, plus its
.git and materialized git-lfs copies) and builds a kallisto index from it, so
it needs roughly REQUIRED_GB of free space. Under Singularity/Apptainer all
of that lands on <output-dir>'s own filesystem (see DAT_WORK_DIR below), and
this script refuses to start if that filesystem hasn't got room, rather than
failing partway through a multi-GB download. Under Docker the bulk lands in
Docker's own storage instead, so the check does not apply to that path.

Environment:
  IMAGE_TAG        Docker image to run, if present. Default: quay.io/hlarnaseq/arcashla-genotype:0.6.0
  SIF_PATH         Singularity image to run instead, if IMAGE_TAG isn't loaded in Docker. Default: modules/local/arcashla/genotype/arcashla-genotype.sif
  IMGTHLA_COMMIT   IMGT/HLA commit to check out. Default: 8d77b3dd93959663d58ae5b626289d0746edd0e7 (version 3.46.0)
  RUNTIME          Force a container runtime: docker, singularity, or apptainer.
                   Default: auto-detect, Docker first (if IMAGE_TAG is loaded),
                   then singularity/apptainer (if SIF_PATH exists).
  DAT_WORK_DIR     Singularity/Apptainer only: writable scratch directory to mount
                   over the image's read-only arcasHLA dat/ directory (see below).
                   Default: a temporary "<output-dir>.build.XXXXXX" sibling, removed
                   on exit. A directory you name yourself is left in place.
  REQUIRED_GB      Singularity/Apptainer only: free space required on the scratch
                   filesystem before starting. Default: 15
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
REQUIRED_GB="${REQUIRED_GB:-15}"

mkdir -p "$1"
OUTPUT_DIR="$(cd "$1" && pwd)"

# --------------------------------------------------------------------------
# Resolve the container runtime.
#
# Auto-detection keeps the original precedence (Docker first, if the image is
# actually loaded, then a .sif). RUNTIME forces one instead - which is what
# makes the Singularity path testable at all on a machine that also has the
# Docker image loaded, and lets a host with both pick the one it wants.
# --------------------------------------------------------------------------
have_docker_image() {
    command -v docker >/dev/null 2>&1 && docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1
}

case "${RUNTIME:-}" in
    docker)
        have_docker_image || {
            echo "ERROR: RUNTIME=docker was requested but Docker image ${IMAGE_TAG} is not available." >&2
            echo "       Run scripts/build_image_arcashla.sh first." >&2
            exit 1
        }
        ;;
    singularity | apptainer)
        command -v "${RUNTIME}" >/dev/null 2>&1 || {
            echo "ERROR: RUNTIME=${RUNTIME} was requested but ${RUNTIME} is not on PATH." >&2
            exit 1
        }
        [[ -f "${SIF_PATH}" ]] || {
            echo "ERROR: RUNTIME=${RUNTIME} was requested but ${SIF_PATH} does not exist." >&2
            echo "       Run scripts/build_image_arcashla.sh first." >&2
            exit 1
        }
        ;;
    "")
        if have_docker_image; then
            RUNTIME="docker"
        elif [[ -f "${SIF_PATH}" ]] && command -v singularity >/dev/null 2>&1; then
            RUNTIME="singularity"
        elif [[ -f "${SIF_PATH}" ]] && command -v apptainer >/dev/null 2>&1; then
            RUNTIME="apptainer"
        else
            echo "ERROR: neither a loaded Docker image (${IMAGE_TAG}) nor a built Singularity/Apptainer image (${SIF_PATH}) was found." >&2
            echo "       Run scripts/build_image_arcashla.sh first." >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: RUNTIME=${RUNTIME} is not one of: docker, singularity, apptainer." >&2
        exit 1
        ;;
esac

# Container-internal mount points, made unique per run: Singularity mounts the
# HOST /tmp into the container by default, so a fixed path here is a shared
# host path that two users - or two concurrent runs by the same user - would
# collide on.
REF_OUT="/tmp/arcashla-reference-out.$$"
DAT_MOUNT="/tmp/arcashla-dat.$$"

# Shell snippet, run INSIDE the container, that prints this arcasHLA install's
# own directory. Discovered rather than hardcoded to /opt/conda/share/... for
# the same reason ARCASHLA_GENOTYPE discovers it (see
# modules/local/arcashla/genotype/main.nf): the exact
# "arcas-hla-<version>-<build>" folder name is not itself pinned, since nf-core
# pinning rules cover channel::version and not build strings.
FIND_ARCASHLA_HOME='
ARCASHLA_PREFIX="$(cd "$(dirname "$(command -v arcasHLA)")/.." && pwd)"
find "${ARCASHLA_PREFIX}/share" -maxdepth 1 -iname "arcas-hla-*" -type d | head -n1
'

# The reference-build command run inside the container: locate this
# arcasHLA install's own share/dat directory, clone IMGTHLA and pin it to
# IMGTHLA_COMMIT ourselves (see usage() above for why), run arcasHLA
# reference --rebuild against that pinned checkout, then copy just dat/ref
# (the kallisto index + processed sequences genotype reads - not the ~4GB raw
# IMGT/HLA git checkout under dat/IMGTHLA, which only exists to build dat/ref)
# to a fixed, container-internal path. This is deliberately NOT the
# bind-mounted output directory itself: the mambaorg/micromamba base image
# runs as a non-root user by default, which generally cannot write into a
# bind-mounted host directory it doesn't own (this pipeline's own
# nextflow.config docker profile works around the same class of problem for
# its own container runs, via `docker.runOptions = '-u $(id -u):$(id -g)'` -
# but forcing that here risks breaking the *earlier* steps above instead, if
# the invoking host user's UID happens not to match whatever UID this image's
# /opt/conda is actually owned by).
BUILD_CMD="
set -euo pipefail
ARCASHLA_HOME=\"\$(${FIND_ARCASHLA_HOME})\"
if [[ -z \"\${ARCASHLA_HOME}\" ]]; then
    echo 'ERROR: could not locate the arcasHLA installation directory inside the image' >&2
    exit 1
fi
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

CONTAINER_ID=""
DAT_WORK=""
CLEANUP_DAT_WORK=0

cleanup() {
    if [[ -n "${CONTAINER_ID}" ]]; then
        docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
    fi
    # Only ever removes a directory this script created itself with mktemp; a
    # DAT_WORK_DIR the caller named is left alone.
    if (( CLEANUP_DAT_WORK )) && [[ -n "${DAT_WORK}" && -d "${DAT_WORK}" ]]; then
        rm -rf "${DAT_WORK}"
    fi
}
trap cleanup EXIT

if [[ "${RUNTIME}" == "docker" ]]; then
    echo "Running arcasHLA reference via Docker image ${IMAGE_TAG} ..."
    # docker cp (run as whoever invoked this script, on the host side) writes
    # the result to OUTPUT_DIR - unlike a bind mount, this never touches the
    # container's own (possibly restricted) view of the host filesystem, so
    # it works regardless of which UID the image happens to run as. The build
    # itself writes into the container's own writable layer, which Docker
    # gives every container over the read-only image by default.
    CONTAINER_ID="$(docker create "${IMAGE_TAG}" bash -c "${BUILD_CMD}")"
    docker start -a "${CONTAINER_ID}"
    docker cp "${CONTAINER_ID}:${REF_OUT}/." "${OUTPUT_DIR}"
else
    # ----------------------------------------------------------------------
    # Singularity/Apptainer.
    #
    # A .sif is a read-only SquashFS at exec time - for EVERY user, root
    # included. There is no writable layer over it the way Docker gives one,
    # so BUILD_CMD's writes into the arcasHLA install tree
    # (dat/IMGTHLA for the clone, dat/ref for the built reference) cannot land
    # in the image; without the bind below they fail outright with
    # "Read-only file system". This is not the UID/ownership problem the
    # Docker branch works around above - Singularity does run as the invoking
    # host user, and that is irrelevant here.
    #
    # --writable-tmpfs is NOT the answer (though conf/modules.config does use
    # it for ARCASHLA_GENOTYPE, whose writes are just a symlink swap and a
    # placeholder file): it is a small, RAM-backed, ephemeral overlay, and the
    # ~4 GB IMGT/HLA checkout exhausts it - the "No space left on device"
    # failure already documented in
    # modules/local/arcashla/genotype/main.nf.
    #
    # Instead, mount a writable host directory over the image's own dat/. It
    # is SEEDED from the image first, because a bare bind over an empty
    # directory would HIDE what dat/ already holds: 1.2 MB of static data
    # under dat/info (decoys_alts.json, hla_freq.tsv, parameters.json) that
    # arcasHLA reads, plus whatever baseline dat/ref content the arcas-hla
    # package ships - in this image that is nothing, since the Dockerfile
    # empties dat/ref deliberately, but that is the image's choice and not
    # something to hardcode an assumption about here.
    # ----------------------------------------------------------------------
    echo "Running arcasHLA reference via ${RUNTIME} image ${SIF_PATH} ..."

    ARCASHLA_HOME="$("${RUNTIME}" exec "${SIF_PATH}" bash -c "${FIND_ARCASHLA_HOME}")"
    if [[ -z "${ARCASHLA_HOME}" ]]; then
        echo "ERROR: could not locate the arcasHLA installation directory inside ${SIF_PATH}." >&2
        exit 1
    fi

    if [[ -n "${DAT_WORK_DIR:-}" ]]; then
        mkdir -p "${DAT_WORK_DIR}"
        DAT_WORK="$(cd "${DAT_WORK_DIR}" && pwd)"
    else
        # Deliberately a sibling of OUTPUT_DIR rather than $TMPDIR: on HPC
        # $TMPDIR is routinely a small tmpfs or a per-job scratch, which would
        # reproduce the same "no space" failure this is meant to avoid. Being
        # on OUTPUT_DIR's filesystem is also what makes the single free-space
        # check below cover both directories.
        DAT_WORK="$(mktemp -d "${OUTPUT_DIR}.build.XXXXXX")"
        CLEANUP_DAT_WORK=1
    fi

    # Fail on the cheap, obvious problem now rather than after a multi-GB
    # clone and LFS pull. POSIX `df -Pk` for portability; column 4 is the
    # available space in 1 KB blocks, and df resolves the mount point itself,
    # so this is correct wherever DAT_WORK actually lives.
    AVAILABLE_KB="$(df -Pk "${DAT_WORK}" | awk 'NR == 2 { print $4 }')"
    REQUIRED_KB=$(( REQUIRED_GB * 1024 * 1024 ))
    if [[ -z "${AVAILABLE_KB}" ]]; then
        echo "WARNING: could not determine free space on ${DAT_WORK}; skipping the space check." >&2
    elif (( AVAILABLE_KB < REQUIRED_KB )); then
        echo "ERROR: not enough free space on ${DAT_WORK}'s filesystem." >&2
        echo "       Need ~${REQUIRED_GB} GB (the IMGT/HLA checkout, its .git and git-lfs copies," >&2
        echo "       and the built kallisto index), have $(( AVAILABLE_KB / 1024 / 1024 )) GB." >&2
        echo "       Point <output-dir> (or DAT_WORK_DIR) at a larger filesystem, or override" >&2
        echo "       REQUIRED_GB if you know better." >&2
        exit 1
    fi

    echo "Seeding writable arcasHLA dat/ at ${DAT_WORK} from ${ARCASHLA_HOME}/dat ..."
    "${RUNTIME}" exec \
        --bind "${DAT_WORK}:${DAT_MOUNT}" \
        "${SIF_PATH}" \
        cp -a "${ARCASHLA_HOME}/dat/." "${DAT_MOUNT}/"

    "${RUNTIME}" exec \
        --bind "${DAT_WORK}:${ARCASHLA_HOME}/dat" \
        --bind "${OUTPUT_DIR}:${REF_OUT}" \
        "${SIF_PATH}" \
        bash -c "${BUILD_CMD}"
fi

if [[ ! -s "${OUTPUT_DIR}/hla.idx" ]]; then
    echo "ERROR: ${OUTPUT_DIR}/hla.idx is missing or empty after the build - check the output above for the actual failure and re-run." >&2
    exit 1
fi

echo
echo "Built arcasHLA reference (IMGT/HLA ${IMGTHLA_COMMIT}) at ${OUTPUT_DIR}."
echo "Use it with: --arcashla_reference_dir ${OUTPUT_DIR}"
