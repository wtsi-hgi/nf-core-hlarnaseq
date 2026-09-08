process ARCASHLA_GENOTYPE {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // nextflow.config sets docker.registry/singularity.registry = 'quay.io'
    // for every container engine, so a bare "hlarnaseq/..." tag would
    // resolve as quay.io/hlarnaseq/... and fail to pull (nothing is pushed
    // there). Docker matches a local image already tagged with that full
    // reference with no network access; Singularity/Apptainer have no
    // access to Docker's local image store at all, so they instead
    // reference a local .sif file built from that same image (see
    // scripts/build_image_arcashla.sh) directly by path - Nextflow uses a
    // local file as-is, no pull, no registry involved.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${moduleDir}/arcashla-genotype.sif" :
        'quay.io/hlarnaseq/arcashla-genotype:0.6.0' }"

    publishDir "${params.outdir}/arcashla/genotype",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(meta), path(reads)
    // Taken as a staged input rather than read from params directly inside the
    // script, so Nextflow resolves its real path and adds it to the container
    // bind list itself (singularity.autoMounts / Docker volume mapping). A raw
    // "${params.arcashla_reference_dir}" interpolation is invisible to that
    // machinery, so a reference living anywhere outside an already-bound path -
    // e.g. behind a host symlink onto another filesystem - produced a dangling
    // dat/ref inside the container and arcasHLA's confusing
    // "FileNotFoundError: .../dat/ref/hla.p.json". This is the same reason
    // HLALA_TYPING takes its graph as path(graph). stageAs pins the in-task
    // name so the script does not depend on what the operator called their
    // directory and cannot collide with the staged FASTQs.
    path(arcashla_reference, stageAs: 'arcashla_reference')

    output:
    tuple val(meta), path("${meta.id}.genotype.json"), emit: genotype
    tuple val(meta), path("${meta.id}.genotype.log"), emit: log
    path "versions.yml", emit: versions

    script:
    def read1 = reads[0]
    def read2 = reads[1]
    """
    command -v arcasHLA >/dev/null 2>&1 || {
        echo "ERROR: arcasHLA is not available in the active environment" >&2
        exit 127
    }

    # Locate this arcasHLA install's own share/dat directory. The exact
    # "arcas-hla-<version>-<build>" folder name is not itself pinned (nf-core
    # pinning rules cover channel::version, not build strings, since they
    # vary by platform), so it is discovered at runtime instead of hardcoded.
    ARCASHLA_PREFIX="\$(cd "\$(dirname "\$(command -v arcasHLA)")/.." && pwd)"
    ARCASHLA_HOME="\$(find "\${ARCASHLA_PREFIX}/share" -maxdepth 1 -iname 'arcas-hla-*' -type d | head -n1)"
    if [[ -z "\${ARCASHLA_HOME}" ]]; then
        echo "ERROR: could not locate the arcasHLA installation directory under \${ARCASHLA_PREFIX}/share" >&2
        exit 1
    fi

    # The staged reference has to actually resolve from inside the task - under
    # a container that means Nextflow bound its real path in. Checked here, up
    # front, rather than left to fail later as arcasHLA's
    # "FileNotFoundError: .../dat/ref/hla.p.json", which says nothing about a
    # missing mount being the cause. -s follows symlinks, so this exercises the
    # whole chain (staged symlink -> real path) exactly as arcasHLA will.
    ARCASHLA_REF_SOURCE="\$PWD/arcashla_reference"
    for ref_file in hla.idx hla.p.json; do
        if [[ ! -s "\${ARCASHLA_REF_SOURCE}/\${ref_file}" ]]; then
            echo "ERROR: the staged arcasHLA reference has no readable \${ref_file} (\${ARCASHLA_REF_SOURCE}/\${ref_file})." >&2
            echo "       If that path is a dangling symlink, its target was not mounted into the container; if it is empty or incomplete, build the reference with scripts/build_arcashla_reference.sh and pass it as --arcashla_reference_dir." >&2
            ls -la "\${ARCASHLA_REF_SOURCE}/" >&2 || true
            exit 1
        fi
    done

    # arcasHLA has no option to point genotype at an external reference; it
    # always reads dat/ref beneath its own install. --arcashla_reference_dir
    # is a pre-built reference (IMGT/HLA + kallisto index; see
    # scripts/build_arcashla_reference.sh), prepared once, out of band, the
    # same way --hlala_graph_dir is for HLA-LA. It arrives here as the staged
    # 'arcashla_reference' input (see the input block for why that matters),
    # and dat/ref is pointed at it with a symlink swap: unlike building the
    # reference in-place, this is fast and atomic, so it's safe to redo
    # unconditionally on every task with no locking, whether the task got a
    # fresh Conda environment or a fresh container instance.
    #
    # Guard against a real (non-symlink) dat/ref that already has a real
    # reference built into it: a freshly installed arcas-hla package's
    # dat/ref is NOT empty - build.sh copies the source repo's dat/ tree
    # as-is, which ships some baseline files (allele_groups.json, cDNA
    # JSONs, tiny placeholder GRCh38.*.fasta stubs) - but never hla.idx (the
    # kallisto index), hla.fasta, hla.convert.json, or the hla_partial.*
    # equivalents, all of which only `arcasHLA reference` itself produces.
    # hla.idx is therefore the correct signal for "a real reference already
    # exists here" - checking for any content at all (an earlier version of
    # this guard did) false-positives on every fresh install/container
    # image, exactly the case this is supposed to allow through.
    ARCASHLA_REF_TARGET="\${ARCASHLA_HOME}/dat/ref"
    mkdir -p "\${ARCASHLA_HOME}/dat"
    if [[ -d "\${ARCASHLA_REF_TARGET}" && ! -L "\${ARCASHLA_REF_TARGET}" && -s "\${ARCASHLA_REF_TARGET}/hla.idx" ]]; then
        echo "ERROR: \${ARCASHLA_REF_TARGET}/hla.idx already exists in a real directory (not a symlink) - refusing to replace it with --arcashla_reference_dir to avoid destroying whatever is already there. ARCASHLA_GENOTYPE expects a fresh Conda environment (-profile conda) or its own container image, not an ambient environment with its own reference already built." >&2
        exit 1
    fi
    rm -rf "\${ARCASHLA_REF_TARGET}"
    ln -s "\${ARCASHLA_REF_SOURCE}" "\${ARCASHLA_REF_TARGET}"

    # `arcasHLA genotype` independently imports and calls reference.py's own
    # check_ref(), which - regardless of dat/ref already being correctly in
    # place above - decides whether a reference exists solely by checking
    # whether dat/IMGTHLA/hla.dat is present, and if not, tries to fetch and
    # rebuild everything itself (re-cloning the ~4GB IMGT/HLA database, this
    # time into a size-limited --writable-tmpfs overlay, hence "No space
    # left on device"; and needing dat/IMGTHLA/wmda/hla_nom_p.txt, which was
    # never fetched to begin with in this design). Its content is never
    # actually read once check_ref() finds it present - only presence is
    # checked - so a placeholder is sufficient and avoids needing to ship
    # any of dat/IMGTHLA via --arcashla_reference_dir.
    mkdir -p "\${ARCASHLA_HOME}/dat/IMGTHLA"
    if [[ ! -e "\${ARCASHLA_HOME}/dat/IMGTHLA/hla.dat" ]]; then
        echo "placeholder - dat/ref (symlinked above) is the real, already-built reference; this file exists only to satisfy arcasHLA's own check_ref() presence check, which never reads its content once found" \\
            > "\${ARCASHLA_HOME}/dat/IMGTHLA/hla.dat"
    fi

    arcasHLA genotype \\
        "${read1}" \\
        "${read2}" \\
        -g "${params.arcashla_genes}" \\
        -o . \\
        -t ${task.cpus} \\
        -v

    derived_sample=\$(basename "${read1}")
    derived_sample="\${derived_sample%%.*}"

    if [[ "\${derived_sample}.genotype.json" != "${meta.id}.genotype.json" ]]; then
        cp "\${derived_sample}.genotype.json" "${meta.id}.genotype.json"
    fi
    if [[ "\${derived_sample}.genotype.log" != "${meta.id}.genotype.log" ]]; then
        cp "\${derived_sample}.genotype.log" "${meta.id}.genotype.log"
    fi

    # arcasHLA has no --version flag: best-effort parse the installed package
    # directory name (e.g. "arcas-hla-0.6.0-2") from conda-meta, falling back
    # to "unknown" if it cannot be resolved.
    set +e
    arcashla_pkg=\$(basename \$(ls "\${ARCASHLA_PREFIX}"/conda-meta/arcas-hla-*.json 2>/dev/null | head -n1) 2>/dev/null)
    set -e
    if [[ -n "\${arcashla_pkg}" ]]; then
        arcashla_version="\${arcashla_pkg#arcas-hla-}"
        arcashla_version="\${arcashla_version%.json}"
    else
        arcashla_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        arcasHLA: "\${arcashla_version}"
    END_VERSIONS
    """

    stub:
    """
    touch "${meta.id}.genotype.json"
    touch "${meta.id}.genotype.log"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        arcasHLA: "unknown"
    END_VERSIONS
    """
}
