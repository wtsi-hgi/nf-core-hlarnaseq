process HIBAG_PREDICT {
    tag "$meta.id"
    label 'process_single'

    // Deliberately no `conda`/`container` directive in this iteration: HIBAG
    // is taken from the ambient environment, as HLAPM_* modules do today. The
    // requirement is recorded in envs/nf-core.yml. Moving this module onto the
    // standard nf-core environment.yml + container pattern is a planned
    // follow-up iteration.

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
    command -v Rscript >/dev/null 2>&1 || {
        echo "ERROR: Rscript is not available in the active environment." >&2
        exit 127
    }
    Rscript -e 'if (!requireNamespace("HIBAG", quietly=TRUE)) { quit(status=1) }' || {
        echo "ERROR: the R package HIBAG is not installed in the active environment. Install bioconductor-hibag (see envs/nf-core.yml)." >&2
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
