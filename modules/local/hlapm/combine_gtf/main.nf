process HLAPM_COMBINE_GTF {
    tag "hlapm_combine_gtf"
    label 'process_single'

    publishDir "${params.outdir}/hlapm/quantify",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename.equals('versions.yml') ? null : filename }

    input:
    path gtfs

    output:
    path "combined.gtf", emit: gtf
    path "versions.yml", emit: versions

    script:
    """
    set -euo pipefail

    cat *.gtf | grep -v '^#' > combined.gtf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bash: \$(bash --version | head -n1 | sed 's/^GNU bash, version //; s/ .*//')
    END_VERSIONS
    """
}
