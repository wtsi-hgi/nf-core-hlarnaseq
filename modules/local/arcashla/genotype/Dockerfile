# nf-core/hlarnaseq: ARCASHLA_GENOTYPE container image.
#
# Installs the same pinned arcasHLA + kallisto versions declared in this
# module's environment.yml. That's all - it deliberately does NOT build the
# arcasHLA IMGT/HLA + kallisto reference here.
#
# Why: arcasHLA has no option to point `genotype` at an external reference
# database at runtime - whatever reference exists inside its own install
# (share/arcas-hla-*/dat/ref) is the one used - but building it
# (`arcasHLA reference`) clones the ~4GB github.com/ANHIG/IMGTHLA database,
# which is slow and a poor fit for an automated image build (a transient
# network hiccup fails the whole build). Instead, main.nf symlinks
# dat/ref to an externally-supplied --arcashla_reference_dir at task runtime
# (the same pattern this pipeline already uses for HLA-LA's
# --hlala_graph_dir), and scripts/build_arcashla_reference.sh builds that
# directory once, out of band, using this same image.
FROM mambaorg/micromamba:1.5.8

ARG MAMBA_DOCKERFILE_ACTIVATE=1

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yml /tmp/environment.yml
RUN micromamba install -y -n base -f /tmp/environment.yml \
    && micromamba clean --all --yes
