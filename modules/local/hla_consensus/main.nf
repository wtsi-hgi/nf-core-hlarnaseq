process HLA_CONSENSUS {
    tag "hla_consensus"
    label 'process_single'

    publishDir "${params.outdir}/hla_consensus",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    path arcashla_combined_csv
    path hlala_combined_tsv
    path sample_key
    path rna_excluded_samples, stageAs: 'rna_excluded_samples.optional.txt'
    path wgs_excluded_samples, stageAs: 'wgs_excluded_samples.optional.txt'

    output:
    path "hla_consensus.rna_wgs_rna-hla_with_consensus.tsv", emit: summary
    path "hla_consensus.rna_wgs_hla_consensus.tsv", emit: consensus
    path "versions.yml", emit: versions

    script:
    def rna_excl_arg = params.rna_excluded_samples ? "--rna-excluded-samples ${rna_excluded_samples}" : ""
    def wgs_excl_arg = params.wgs_excluded_samples ? "--wgs-excluded-samples ${wgs_excluded_samples}" : ""
    """
    call_hla_consensus.py \\
        --arcashla-csv ${arcashla_combined_csv} \\
        --hlala-file ${hlala_combined_tsv} \\
        --sample-key ${sample_key} \\
        --output-prefix hla_consensus \\
        --truncate-fields ${params.hla_consensus_truncate_fields} \\
        ${rna_excl_arg} \\
        ${wgs_excl_arg}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python3: \$(python3 --version | sed 's/Python //')
        pandas: \$(python3 -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """
}
