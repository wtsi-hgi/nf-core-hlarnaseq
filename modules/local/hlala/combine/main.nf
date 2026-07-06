process HLALA_COMBINE {
    tag "HLA-LA_combined"
    label 'process_single'

    publishDir "${params.outdir}/hlala",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(sample_ids), path(bestguess_files)

    output:
    path "HLA-LA_combined.csv", emit: csv
    path "versions.yml", emit: versions

    script:
    def manifest = (0..<sample_ids.size()).collect { i -> "${sample_ids[i]}\t${bestguess_files[i].name}" }.join('\n')
    """
    cat > hlala_manifest.tsv <<'EOF'
    ${manifest}
    EOF

    printf "sample_id,HLA_allele\\n" > HLA-LA_combined.csv
    sort -t \$'\\t' -k1,1 hlala_manifest.tsv | while IFS=\$'\\t' read -r sample_id bestguess_file; do
        tail -n +2 "\${bestguess_file}" \\
            | awk -F '\\t' -v sample_id="\${sample_id}" 'NF >= 3 && \$3 != "" { print sample_id "," \$3 }'
    done >> HLA-LA_combined.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        HLA-LA-combine: "local"
    END_VERSIONS
    """
}
