process HLAPM_PREPARE_INPUT {
    tag "hlapm_prepare_input"
    label 'process_single'

    // Shared python3 + R environment, not module-local: see
    // containers/datatools/README.md. This script needs only the Python
    // standard library, but shares the image rather than carrying a
    // near-empty environment of its own.
    conda "${projectDir}/containers/datatools/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${projectDir}/containers/datatools/datatools.sif" :
        'quay.io/hlarnaseq/datatools:1.0' }"

    publishDir "${params.outdir}/hlapm/input",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    path hla_consensus_key, stageAs: 'hla_consensus_key.input'

    output:
    path "*.tsv", emit: sample_tsvs
    path "versions.yml", emit: versions

    script:
    """
    # See HLA_CONSENSUS for why this guard exists: with no
    # conda/docker/singularity/apptainer profile the task falls back to the
    # host PATH, and an actionable message beats a bare "command not found".
    command -v python3 >/dev/null 2>&1 || {
        echo "ERROR: python3 is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in containers/datatools/environment.yml." >&2
        exit 127
    }

    consensus_to_hlapm.py \\
        --consensus-tsv ${hla_consensus_key} \\
        --output-dir . \\
        --allowed-loci ${params.hlapm_allowed_loci}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python3: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}
