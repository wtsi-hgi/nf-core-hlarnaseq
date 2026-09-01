process HIBAG_PREDICT {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // Standard nf-core pattern: one environment.yml feeds the `conda`
    // directive, paired with the matching pinned Biocontainers image built
    // from that same Bioconda recipe.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hibag:1.42.0--r44he5774e6_1':
        'quay.io/biocontainers/bioconductor-hibag:1.42.0--r44he5774e6_1' }"

    publishDir "${params.outdir}/hibag",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(meta), path(bed), path(bim), path(fam)
    path model

    output:
    tuple val(meta), path("*.hibag_calls.tsv"), emit: calls
    tuple val(meta), path("*.hibag_posterior.tsv"), emit: posterior
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def loci_arg = params.hibag_loci ? "--loci '${params.hibag_loci}'" : ""
    """
    # The conda/container directives above provision R and HIBAG. Neither
    # applies when the pipeline is run with no -profile conda/docker/
    # singularity/apptainer at all, in which case the task falls back to the
    # host PATH - fail with an actionable message rather than a bare
    # "command not found", as ARCASHLA_VALIDATE_FASTQ does.
    command -v Rscript >/dev/null 2>&1 || {
        echo "ERROR: Rscript is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in modules/local/hibag/predict/environment.yml." >&2
        exit 127
    }
    Rscript -e 'if (!requireNamespace("HIBAG", quietly=TRUE)) { quit(status=1) }' || {
        echo "ERROR: the R package HIBAG is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in modules/local/hibag/predict/environment.yml." >&2
        exit 127
    }

    hibag_predict.R \\
        --bed ${bed} \\
        --bim ${bim} \\
        --fam ${fam} \\
        --model ${model} \\
        --out-prefix ${prefix} \\
        --match-type '${params.hibag_match_type}' \\
        --assembly '${params.hibag_assembly}' \\
        --min-prob '${params.hibag_min_prob}' \\
        --min-matched-snps '${params.hibag_min_matched_snps}' \\
        ${loci_arg}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: \$(Rscript -e 'cat(paste(R.version\$major, R.version\$minor, sep="."))')
        HIBAG: \$(Rscript -e 'cat(as.character(packageVersion("HIBAG")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # A stub call in the same shape the real script emits, so -stub-run keeps
    # the downstream HLA-LA-compatible contract (header plus two allele rows
    # per locus, every allele containing '*') without needing R or HIBAG.
    printf 'sample_id\\tLocus\\tHLA_allele\\n' > ${prefix}.hibag_calls.tsv
    printf '%s\\tA\\tA*01:01\\n' '${meta.id}' >> ${prefix}.hibag_calls.tsv
    printf '%s\\tA\\tA*11:01\\n' '${meta.id}' >> ${prefix}.hibag_calls.tsv

    printf 'sample_id\\tlocus\\tallele1\\tallele2\\tprob\\tmatching\\tn_model_snps\\tn_matched_snps\\n' > ${prefix}.hibag_posterior.tsv
    printf '%s\\tA\\t01:01\\t11:01\\t1\\t1\\t0\\t0\\n' '${meta.id}' >> ${prefix}.hibag_posterior.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "stub"
        HIBAG: "stub"
    END_VERSIONS
    """
}
