process HLAPM_COMBINE_GTF {
    tag "hlapm_combine_gtf"
    label 'process_single'

    // Shared environment, not module-local: see containers/datatools/README.md
    // ("The shell-only consumers"). Pure shell (cat/grep), same rationale as
    // HLALA_COMBINE.
    conda "${projectDir}/containers/datatools/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${projectDir}/containers/datatools/datatools.sif" :
        'quay.io/hlarnaseq/datatools:1.1' }"

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
