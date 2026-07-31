process ARCASHLA_GENOTYPE {
    tag "$meta.id"
    label 'process_medium'

    publishDir "${params.outdir}/arcashla/genotype",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.genotype.json"), emit: genotype
    tuple val(meta), path("${meta.id}.genotype.log"), emit: log
    path "versions.yml", emit: versions

    script:
    def read1 = reads[0]
    def read2 = reads[1]
    """
    ARCASHLA_CONDA_ENV="arcas-hla"

    command -v conda >/dev/null 2>&1 || {
        echo "ERROR: conda is required to run arcasHLA genotype from the \${ARCASHLA_CONDA_ENV} environment" >&2
        exit 127
    }

    conda run -n "\${ARCASHLA_CONDA_ENV}" bash -lc 'command -v arcasHLA >/dev/null 2>&1' || {
        echo "ERROR: arcasHLA is not available in the \${ARCASHLA_CONDA_ENV} Conda environment" >&2
        exit 127
    }

    conda run -n "\${ARCASHLA_CONDA_ENV}" arcasHLA genotype \\
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
    # directory name (e.g. "arcas-hla-0.6.0-1") from the arcas-hla env's
    # conda-meta, falling back to "unknown" if it cannot be resolved.
    set +e
    arcashla_prefix=\$(conda run -n "\${ARCASHLA_CONDA_ENV}" bash -lc 'echo "\$CONDA_PREFIX"' 2>/dev/null)
    arcashla_pkg=\$(basename \$(ls "\${arcashla_prefix}"/conda-meta/arcas-hla-*.json 2>/dev/null | head -n1) 2>/dev/null)
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
