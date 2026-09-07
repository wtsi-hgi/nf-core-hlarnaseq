process HLA_CONSENSUS {
    tag "hla_consensus"
    label 'process_single'

    // Shared python3 + R environment, not module-local: see
    // containers/datatools/README.md. Under -profile singularity/apptainer the
    // image is referenced as a local .sif by path (built by
    // scripts/build_image_datatools.sh); under -profile docker as a
    // quay.io-prefixed tag matching nextflow.config's docker.registry, which
    // Docker resolves against its local image store with no network access.
    conda "${projectDir}/containers/datatools/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${projectDir}/containers/datatools/datatools.sif" :
        'quay.io/hlarnaseq/datatools:1.0' }"

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
    # The conda/container directives above provision python3 and pandas.
    # Neither applies when the pipeline is run with no -profile
    # conda/docker/singularity/apptainer at all, in which case the task falls
    # back to the host PATH - fail with an actionable message rather than a
    # bare ImportError, as HIBAG_PREDICT does.
    python3 -c "import pandas" >/dev/null 2>&1 || {
        echo "ERROR: python3 with pandas is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in containers/datatools/environment.yml." >&2
        exit 127
    }

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
