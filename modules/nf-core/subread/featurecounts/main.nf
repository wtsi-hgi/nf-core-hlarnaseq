process SUBREAD_FEATURECOUNTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/subread:2.1.1--h577a1d6_0'
        : 'quay.io/biocontainers/subread:2.1.1--h577a1d6_0'}"

    input:
    tuple val(meta), path(bams), path(annotation)

    output:
    tuple val(meta), path("*featureCounts.tsv"), emit: counts
    tuple val(meta), path("*featureCounts.tsv.summary"), emit: summary
    tuple val(meta), path("*.featureCounts.bam"), emit: bam, optional: true
    tuple val("${task.process}"), val('subread'), eval("featureCounts -v 2>&1 | sed -n 's/^featureCounts v//p'"), emit: versions_subread, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def paired_end = meta.single_end ? '' : '-p'

    def strandedness = 0
    if (meta.strandedness == 'forward') {
        strandedness = 1
    }
    else if (meta.strandedness == 'reverse') {
        strandedness = 2
    }
    """
    featureCounts \\
        ${args} \\
        ${paired_end} \\
        -T ${task.cpus} \\
        -a ${annotation} \\
        -s ${strandedness} \\
        -o ${prefix}.featureCounts.tsv \\
        ${bams.join(' ')}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    // -R BAM's reannotated-per-read output keeps each input BAM's own
    // filename (with .featureCounts.bam appended), not `prefix` - only
    // touched when ext.args actually requests -R BAM, so the un-changed,
    // non-`-R BAM` call (e.g. COUNTS_COMMONREF's SUBREAD_FEATURECOUNTS) is
    // unaffected.
    def bam_list = (bams instanceof List ? bams : [bams])
    def r_bam_stub = (task.ext.args ?: '').contains('-R BAM')
        ? bam_list.collect { "touch ${it}.featureCounts.bam" }.join('\n    ')
        : ''
    """
    touch ${prefix}.featureCounts.tsv
    touch ${prefix}.featureCounts.tsv.summary
    ${r_bam_stub}
    """
}
