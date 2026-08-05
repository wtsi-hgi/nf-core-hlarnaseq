process HLAPM_PREPARE_INPUT {
    tag "hlapm_prepare_input"
    label 'process_single'

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
