process HLALA_RUN {
    tag "$meta.id"
    label 'process_medium'

    publishDir "${params.outdir}/hlala",
        mode: params.publish_dir_mode,
        saveAs: { filename ->
            if (filename == 'versions.yml') {
                return null
            }
            if (filename.contains('.R1_bestguess_G.txt')) {
                return null
            }
            return filename
        }

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("${meta.id}.R1_bestguess_G.txt"), emit: bestguess_g
    tuple val(meta), path("${meta.id}/R1_bestguess_G.txt"), emit: published_bestguess_g
    tuple val(meta), path("${meta.id}/R1_bestguess.txt"), optional: true, emit: bestguess
    tuple val(meta), path("${meta.id}/hla.tar.gz"), optional: true, emit: archive
    tuple val(meta), path("${meta.id}/hlala.log"), emit: log
    path "versions.yml", emit: versions

    script:
    """
    sample_id="${meta.id}"
    HLALA_CONDA_ENV="hla-la"

    command -v conda >/dev/null 2>&1 || {
        echo "ERROR: conda is required to run HLA-LA from the \${HLALA_CONDA_ENV} environment" >&2
        exit 127
    }

    conda run -n "\${HLALA_CONDA_ENV}" bash -lc 'command -v HLA-LA.pl >/dev/null 2>&1' || {
        echo "ERROR: HLA-LA.pl is not available in the \${HLALA_CONDA_ENV} Conda environment" >&2
        exit 127
    }

    if [[ "${bai}" != "${bam}.bai" ]]; then
        ln -sf "${bai}" "${bam}.bai"
    fi

    mkdir -p hlala_work

    conda run -n "\${HLALA_CONDA_ENV}" HLA-LA.pl \\
        --BAM "${bam}" \\
        --graph "${params.hlala_graph}" \\
        --customGraphDir "${params.hlala_graph_dir}" \\
        --sampleID "\${sample_id}" \\
        --maxThreads ${task.cpus} \\
        --workingDir hlala_work \\
        > hlala.log 2>&1

    cp "hlala_work/\${sample_id}/hla/R1_bestguess_G.txt" R1_bestguess_G.txt
    cp R1_bestguess_G.txt "${meta.id}.R1_bestguess_G.txt"
    mkdir -p "\${sample_id}"
    cp R1_bestguess_G.txt "\${sample_id}/R1_bestguess_G.txt"

    if [[ -f "hlala_work/\${sample_id}/hla/R1_bestguess.txt" ]]; then
        cp "hlala_work/\${sample_id}/hla/R1_bestguess.txt" R1_bestguess.txt
        cp R1_bestguess.txt "\${sample_id}/R1_bestguess.txt"
    fi

    if [[ -d "hlala_work/\${sample_id}/hla" ]]; then
        tar -czf hla.tar.gz -C "hlala_work/\${sample_id}" hla
        cp hla.tar.gz "\${sample_id}/hla.tar.gz"
    fi

    cp hlala.log "\${sample_id}/hlala.log"

    set +e
    hlala_version=\$(conda run -n "\${HLALA_CONDA_ENV}" HLA-LA.pl --version 2>&1 | head -n 1)
    set -e
    if [[ -z "\${hlala_version}" ]] || [[ "\${hlala_version}" == *"Usage"* ]]; then
        hlala_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        HLA-LA: "\${hlala_version}"
    END_VERSIONS
    """
}
