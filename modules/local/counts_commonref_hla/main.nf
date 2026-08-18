process COUNTS_COMMONREF_HLA_REFORMAT {
    tag "${meta.id}"
    label 'process_single'

    // No module-level publishDir here (unlike e.g. ARCASHLA_EXTRACT/
    // HLA_CONSENSUS's static, meta-independent directories): this process's
    // publish path varies per sample (${meta.id}), which requires a
    // closure-deferred path - a top-level, non-closure publishDir string
    // interpolating ${meta.id} directly would be evaluated at process
    // definition/parse time, before `meta` exists, and fail with
    // "No such variable: meta". conf/modules.config's
    // `withName: 'COUNTS_COMMONREF_HLA_REFORMAT'` block supplies the
    // per-sample path instead, matching HLAPM_QUANTIFY_READS/
    // HLAPM_SUMMARIZE_READCOUNTS's own precedent of omitting publishDir here
    // entirely for the same reason.

    input:
    tuple val(meta), path(bam)
    path gtf

    output:
    tuple val(meta), path("${meta.id}.rnaseq_featurecounts.tsv"), emit: read_gene_assignments
    path "versions.yml", emit: versions

    script:
    """
    set -euo pipefail

    # grep exits 1 when no line matches - a legitimate outcome here (e.g. no
    # reads were assigned to any gene in this region/GTF combination), not an
    # error condition, so it must not abort the script under set -e/pipefail.
    # A real grep failure (any exit status other than 0 or 1) still aborts.
    samtools view "${bam}" \\
        | { grep -e 'Assigned' || test \$? -eq 1; } \\
        > "${meta.id}.assignedreads.txt"

    reformat_rnaseq_featurecounts.py \\
        -i "${meta.id}.assignedreads.txt" \\
        -g "${gtf}" \\
        -o "${meta.id}.rnaseq_featurecounts.tsv"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version | sed -n '1s/^samtools //p')
        python3: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """

    stub:
    // A stub: block is required here (unlike e.g. ARCASHLA_EXTRACT/
    // HLA_CONSENSUS, whose real scripts run unmodified under -stub-run):
    // this process's real script actually parses its BAM input's content
    // (samtools view), and under -stub-run that input is itself a stubbed,
    // empty-touched placeholder (SUBREAD_FEATURECOUNTS_HLA's own stub: -
    // see modules/nf-core/subread/featurecounts/main.nf), which is not a
    // valid BAM and would make a real `samtools view` fail - matching the
    // SAMTOOLS_SORT/HLAPM_QUANTIFY_READS precedent of needing an explicit
    // stub whenever a process's real script would otherwise need to parse
    // an upstream stubbed file's content.
    """
    printf 'read_name\\tdirection\\tgene_name\\tedit_distance\\n' > "${meta.id}.rnaseq_featurecounts.tsv"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: unknown
        python3: unknown
    END_VERSIONS
    """
}
