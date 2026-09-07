process HLAPM_SUMMARIZE_READCOUNTS {
    tag "$meta.id"
    label 'process_single'

    // Shared python3 + R environment, not module-local: see
    // containers/datatools/README.md. This module previously shared the
    // operator-prepared `hlapm-quantify` Conda environment with
    // HLAPM_QUANTIFY_READS; that environment is gone - the Python 2 half
    // became that module's own image, this R half moved here.
    conda "${projectDir}/containers/datatools/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${projectDir}/containers/datatools/datatools.sif" :
        'quay.io/hlarnaseq/datatools:1.0' }"

    input:
    tuple val(meta), path(edit_distance_tsv)

    output:
    tuple val(meta), path("${meta.id}.HLA_gene_summary.tsv"), emit: gene_summary
    path "versions.yml",                                      emit: versions

    script:
    """
    # See HLA_CONSENSUS for why this guard exists: with no
    # conda/docker/singularity/apptainer profile the task falls back to the
    # host PATH, and an actionable message beats a bare "command not found".
    command -v Rscript >/dev/null 2>&1 || {
        echo "ERROR: Rscript is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in containers/datatools/environment.yml." >&2
        exit 127
    }

    # Staged onto PATH from bin/ by Nextflow, and carries its own
    # "#!/usr/bin/env Rscript" shebang. Invoked by name rather than as
    # "\${projectDir}/bin/..." because that path does not exist inside a
    # container.
    summarize_hla_readcounts.R "${edit_distance_tsv}" "${params.hlapm_quantify_max_edit_distance}" "${meta.id}.HLA_gene_summary.tsv"

    set +e
    r_version=\$(Rscript -e 'cat(as.character(getRversion()))' 2>&1)
    set -e
    if [[ -z "\${r_version}" ]]; then
        r_version="unknown"
    fi

    set +e
    dplyr_version=\$(Rscript -e 'cat(as.character(packageVersion("dplyr")))' 2>&1)
    set -e
    if [[ -z "\${dplyr_version}" ]]; then
        dplyr_version="unknown"
    fi

    set +e
    tidyr_version=\$(Rscript -e 'cat(as.character(packageVersion("tidyr")))' 2>&1)
    set -e
    if [[ -z "\${tidyr_version}" ]]; then
        tidyr_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "\${r_version}"
        dplyr: "\${dplyr_version}"
        tidyr: "\${tidyr_version}"
    END_VERSIONS
    """

    stub:
    """
    printf 'gene_name\\tn_reads_mapping\\n' > "${meta.id}.HLA_gene_summary.tsv"
    printf 'HLA-A\\t1\\n' >> "${meta.id}.HLA_gene_summary.tsv"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "unknown"
        dplyr: "unknown"
        tidyr: "unknown"
    END_VERSIONS
    """
}
