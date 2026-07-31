process ARCASHLA_COMBINE {
    tag "arcasHLA_combined"
    label 'process_single'

    publishDir "${params.outdir}/arcashla",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(sample_ids), path(genotype_jsons)

    output:
    path "arcasHLA_combined.csv", emit: csv
    path "versions.yml", emit: versions

    script:
    def manifest = (0..<sample_ids.size()).collect { i -> "${sample_ids[i]}\t${genotype_jsons[i].name}" }.join('\n')
    """
    cat > arcashla_manifest.tsv <<'EOF'
    ${manifest}
    EOF

    combine_arcashla_genotypes.R arcashla_manifest.tsv arcasHLA_combined.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: \$(Rscript -e 'cat(as.character(getRversion()))')
        jsonlite: \$(Rscript -e 'cat(as.character(packageVersion("jsonlite")))')
        dplyr: \$(Rscript -e 'cat(as.character(packageVersion("dplyr")))')
        tibble: \$(Rscript -e 'cat(as.character(packageVersion("tibble")))')
        stringr: \$(Rscript -e 'cat(as.character(packageVersion("stringr")))')
        purrr: \$(Rscript -e 'cat(as.character(packageVersion("purrr")))')
    END_VERSIONS
    """

    stub:
    """
    touch arcasHLA_combined.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "unknown"
        jsonlite: "unknown"
        dplyr: "unknown"
        tibble: "unknown"
        stringr: "unknown"
        purrr: "unknown"
    END_VERSIONS
    """
}
