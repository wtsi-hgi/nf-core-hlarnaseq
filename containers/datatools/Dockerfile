# nf-core/hlarnaseq: shared python3 + R data-tools image.
#
# Installs exactly the environment declared alongside it in environment.yml -
# the interpreters and libraries this pipeline's own bin/ analysis scripts
# need. See environment.yml for the consumer list and the pinning rationale,
# and README.md for why this image is shared rather than module-local.
FROM mambaorg/micromamba:1.5.8

ARG MAMBA_DOCKERFILE_ACTIVATE=1

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yml /tmp/environment.yml
RUN micromamba install -y -n base -f /tmp/environment.yml \
    && micromamba clean --all --yes

# The micromamba base image only puts this environment on PATH via an
# entrypoint script that wraps whatever command `docker run` is given.
# Singularity/Apptainer's `exec` (what Nextflow actually uses to run tasks)
# does not honor a Docker image's ENTRYPOINT at all, and neither does
# Nextflow's own task-runner script under either engine - both exec commands
# directly, bypassing that wrapper entirely. Without this, python3/Rscript and
# the libraries this environment provides are installed but unreachable under
# -profile singularity/apptainer.
ENV PATH="${MAMBA_ROOT_PREFIX}/bin:${PATH}"

# Fail the build rather than ship an image that cannot run the scripts it
# exists for: import/load every library the four consumer scripts declare.
# Runs as $MAMBA_USER, which is also how Singularity/Apptainer will read the
# environment (as the invoking host user, not the image's owner).
RUN python3 -c "import pandas; print('pandas', pandas.__version__)" \
    && Rscript -e 'library(jsonlite); library(dplyr); library(tibble); library(stringr); library(purrr); library(tidyr); cat("R libraries ok\n")'
