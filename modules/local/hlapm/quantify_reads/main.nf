process HLAPM_QUANTIFY_READS {
    tag "$meta.id"
    label 'process_medium'

    input:
    tuple val(meta), path(bams)
    path combined_gtf

    output:
    tuple val(meta), path("${meta.id}.edit_distance.tsv"), emit: edit_distance
    tuple val(meta), path("${meta.id}.stat.txt"),          emit: stat
    path "versions.yml",                                  emit: versions

    script:
    def bam_list = (bams instanceof List ? bams : [bams])
    def bam_args = bam_list.collect { "\"${it}\"" }.join(' ')
    """
    HLAPM_QUANTIFY_CONDA_ENV="hlapm-quantify"

    command -v conda >/dev/null 2>&1 || {
        echo "ERROR: conda is required to run make_a_table_210804_allHLAgenes.py from the \${HLAPM_QUANTIFY_CONDA_ENV} environment" >&2
        exit 127
    }

    conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" bash -lc 'command -v python2 >/dev/null 2>&1' || {
        echo "ERROR: python2 is not available in the \${HLAPM_QUANTIFY_CONDA_ENV} Conda environment" >&2
        exit 127
    }

    conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" python2 "${projectDir}/bin/make_a_table_210804_allHLAgenes.py" -g "" -t "" "${combined_gtf}" ${bam_args} > "${meta.id}.edit_distance.tsv" 2> "${meta.id}.stat.txt"

    # make_a_table_210804_allHLAgenes.py has no --version flag of its own;
    # report the Python interpreter version instead (best-effort, matching
    # ARCASHLA_GENOTYPE's precedent for tools without a clean --version flag).
    set +e
    python_version=\$(conda run -n "\${HLAPM_QUANTIFY_CONDA_ENV}" python2 --version 2>&1 | sed 's/^Python //')
    set -e
    if [[ -z "\${python_version}" ]]; then
        python_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python2: "\${python_version}"
    END_VERSIONS
    """

    stub:
    def bam_list = (bams instanceof List ? bams : [bams])
    def header_cols = (['read_name', 'gene_name_confidence', 'gene_name'] + bam_list.collect { it.getName() }).join('\t')
    def stub_row = (['stub_read_1', 'unique', 'placeholder_allele'] + bam_list.collect { 'NA' }).join('\t')
    """
    printf '${header_cols}\\n' > "${meta.id}.edit_distance.tsv"
    printf '${stub_row}\\n' >> "${meta.id}.edit_distance.tsv"

    echo "stub run: no real statistics computed" > "${meta.id}.stat.txt"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python2: "unknown"
    END_VERSIONS
    """
}
