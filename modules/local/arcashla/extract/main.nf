process ARCASHLA_EXTRACT {
    tag "$meta.id"
    label 'process_medium'

    publishDir "${params.outdir}/arcashla/extracted",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(meta), path(bam), path(bai), path(unpaired_reads)

    output:
    tuple val(meta), path("${meta.id}.mhc_1.fq.gz"), path("${meta.id}.mhc_2.fq.gz"), emit: reads
    path "versions.yml", emit: versions

    script:
    def unpaired_r1 = unpaired_reads[0]
    def unpaired_r2 = unpaired_reads[1]
    """
    if [[ "${bai}" != "${bam}.bai" ]]; then
        ln -sf "${bai}" "${bam}.bai"
    fi

    samtools view \
        --uncompressed \
        --fetch-pairs \
        -@ ${task.cpus} \
        -F 2304 \
        "${bam}" \
        "${params.hla_region}" \
        | samtools sort \
            -n \
            -@ ${task.cpus} \
            -T "${meta.id}.sort" \
            -o "${meta.id}.mhc.namesort.bam" \
            -

    samtools fastq \
        -@ ${task.cpus} \
        -0 /dev/null \
        -1 "${meta.id}.bam_1.fq.gz" \
        -2 "${meta.id}.bam_2.fq.gz" \
        -s "${meta.id}.singleton.fq.gz" \
        "${meta.id}.mhc.namesort.bam"

    cat "${unpaired_r1}" "${meta.id}.bam_1.fq.gz" > "${meta.id}.mhc_1.fq.gz"
    cat "${unpaired_r2}" "${meta.id}.bam_2.fq.gz" > "${meta.id}.mhc_2.fq.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version | sed -n '1s/^samtools //p')
    END_VERSIONS
    """
}
