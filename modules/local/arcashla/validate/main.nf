process ARCASHLA_VALIDATE_FASTQ {
    tag "$meta.id"
    label 'process_single'

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
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        validatefastq: \$(validatefastq --version 2>&1 | sed -n 's/^Version: //p')
    END_VERSIONS

    set +e
    validatefastq \
        -i "${read1}" \
        -j "${read2}" \
        > "${meta.id}.validatefastq.log" 2>&1
    validatefastq_status=\$?
    set -e

    if [[ "\${validatefastq_status}" -ne 0 ]] || grep -q '^ERROR' "${meta.id}.validatefastq.log"; then
        cat "${meta.id}.validatefastq.log" >&2
        exit 1
    fi

    cat "${meta.id}.validatefastq.log"
    """
}
