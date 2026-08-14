process HLAPM_SUMMARIZE_READCOUNTS {
    tag "$meta.id"
    label 'process_single'

    input:
    tuple val(meta), path(edit_distance_tsv)

    output:
    tuple val(meta), path("${meta.id}.HLA_gene_summary.tsv"), emit: gene_summary
    path "versions.yml",                                      emit: versions

    script:
    """
    HLAPM_QUANTIFY_CONDA_ENV="hlapm-quantify"

    command -v conda >/dev/null 2>&1 || {
        echo "ERROR: conda is required to run summarize_hla_readcounts.R from the \${HLAPM_QUANTIFY_CONDA_ENV} environment" >&2
        exit 127
    }

    conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" bash -lc 'command -v Rscript >/dev/null 2>&1' || {
        echo "ERROR: Rscript is not available in the \${HLAPM_QUANTIFY_CONDA_ENV} Conda environment" >&2
        exit 127
    }

    conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" Rscript "${projectDir}/bin/summarize_hla_readcounts.R" "${edit_distance_tsv}" "${params.hlapm_quantify_max_edit_distance}" "${meta.id}.HLA_gene_summary.tsv"

    set +e
    r_version=\$(conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" Rscript -e 'cat(as.character(getRversion()))' 2>&1)
    set -e
    if [[ -z "\${r_version}" ]]; then
        r_version="unknown"
    fi

    set +e
    dplyr_version=\$(conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" Rscript -e 'cat(as.character(packageVersion("dplyr")))' 2>&1)
    set -e
    if [[ -z "\${dplyr_version}" ]]; then
        dplyr_version="unknown"
    fi

    set +e
    tidyr_version=\$(conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" Rscript -e 'cat(as.character(packageVersion("tidyr")))' 2>&1)
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
