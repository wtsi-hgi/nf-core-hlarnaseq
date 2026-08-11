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
    // `task.workDir` is not yet assigned while this `script:` preamble runs
    // (Nextflow only creates/assigns the per-task work directory once the
    // rendered script is known, since the script text feeds the task hash).
    // The pipeline-level `workDir` is available at this point instead, so
    // the manifest is written there under a per-task-unique name and
    // referenced by its absolute path below - a single-line interpolation,
    // not multi-line manifest content, so the bash template is not exposed
    // to the indentation-desync bug this replaces.
    def manifest_lines = (0..<sample_ids.size()).collect { i -> "${sample_ids[i]}\t${genotype_jsons[i].name}" }
    def manifest_file  = workDir.resolve("arcashla_manifest_${UUID.randomUUID()}.tsv")
    manifest_file.text = (manifest_lines + ['']).join('\n')
    """
    combine_arcashla_genotypes.R ${manifest_file} arcasHLA_combined.csv

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
    def stub_sample_ids = sample_ids instanceof List ? sample_ids : [sample_ids]
    def stub_rows = stub_sample_ids.collect { sample_id -> "HLA-A,01:01,02:01,${sample_id}" }.join('\n')
    """
    cat <<-END_CSV > arcasHLA_combined.csv
    HLA_gene,allele1_rna,allele2_rna,rna_sample_id
    ${stub_rows}
    END_CSV

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
