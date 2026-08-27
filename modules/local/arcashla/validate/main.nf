process ARCASHLA_VALIDATE_FASTQ {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // Standard nf-core pattern: one environment.yml feeds the `conda`
    // directive, paired with the matching pinned Biocontainers image built
    // from that same Bioconda recipe. Unlike ARCASHLA_GENOTYPE, this module
    // needs no bespoke Dockerfile and no .sif committed to the repo - a
    // maintained public Biocontainer exists for this tool, so both branches
    // below are public references. Mirrors the container-directive shape of
    // the installed nf-core HLALA_TYPING module, including its fully
    // qualified quay.io tag (rather than relying on nextflow.config's
    // docker.registry default).
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopet-validatefastq:0.1.1--hdfd78af_3':
        'quay.io/biocontainers/biopet-validatefastq:0.1.1--hdfd78af_3' }"

    publishDir "${params.outdir}/arcashla/validation",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename.endsWith('.validatefastq.log') ? filename : null }

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path(reads), emit: reads
    tuple val(meta), path("${meta.id}.validatefastq.log"), emit: logs
    path "versions.yml", emit: versions

    script:
    def read1 = reads[0]
    def read2 = reads[1]
    """
    # Bioconda's biopet-validatefastq package - and the Biocontainers image
    # built from it - installs the tool under this name only; there is no
    # plain `validatefastq` alias. Fail with an actionable message rather
    # than a bare "command not found" if neither the conda nor the container
    # directive above provisioned it (which is what happens when the pipeline
    # is run with no -profile conda/docker/singularity/apptainer at all).
    command -v biopet-validatefastq >/dev/null 2>&1 || {
        echo "ERROR: biopet-validatefastq is not available in the active environment or container. Run with -profile conda, docker, singularity, or apptainer so this module can provision it." >&2
        exit 127
    }

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        biopet-validatefastq: \$(biopet-validatefastq --version 2>&1 | sed -n 's/^Version: //p')
    END_VERSIONS

    # validatefastq reports pairing problems as log lines beginning with
    # `ERROR` but still exits 0, so the grep below - not the exit status - is
    # the load-bearing correctness check. Both are kept: a non-zero status
    # additionally covers crashes and unreadable inputs.
    set +e
    biopet-validatefastq \\
        -i "${read1}" \\
        -j "${read2}" \\
        > "${meta.id}.validatefastq.log" 2>&1
    validatefastq_status=\$?
    set -e

    if [[ "\${validatefastq_status}" -ne 0 ]] || grep -q '^ERROR' "${meta.id}.validatefastq.log"; then
        cat "${meta.id}.validatefastq.log" >&2
        exit 1
    fi

    cat "${meta.id}.validatefastq.log"
    """

    stub:
    """
    # Synthetic log in validatefastq's own log4j output format. Unlike a bare
    # `touch`, this keeps -stub-run's published log recognisably a
    # successful-validation log (tests/default.nf.test asserts it contains
    # "no errors found"), while needing neither the tool nor a container
    # image - which is the point of a stub, and what lets -profile test
    # -stub-run stay engine-free and fast.
    cat <<-'END_LOG' > "${meta.id}.validatefastq.log"
    INFO  [stub] [ValidateFastq\$] - Start
    INFO  [stub] [ValidateFastq\$] - Done processing 0 fastq records, no errors found
    INFO  [stub] [ValidateFastq\$] - Done
    END_LOG

    # Hardcoded rather than parsed: environment.yml pins this module to
    # exactly biopet-validatefastq=0.1.1 (the only version Bioconda ships).
    # Bump both together if that pin ever changes.
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        biopet-validatefastq: "0.1.1"
    END_VERSIONS
    """
}
