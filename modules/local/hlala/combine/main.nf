process HLALA_COMBINE {
    tag "HLA-LA_combined"
    label 'process_single'

    publishDir "${params.outdir}/hlala",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    // Every upstream file is now named identically (HLALA_TYPING emits
    // `<prefix>/hla/R1_bestguess_G.txt`, not the per-sample-prefixed name the
    // previous local HLA-LA module produced), so they would collide when
    // staged side by side into this one task directory. `stageAs: "?/*"` puts
    // each into its own numbered subdirectory instead.
    tuple val(sample_ids), path(bestguess_files, stageAs: "?/*")

    output:
    path "HLA-LA_combined.tsv", emit: csv
    path "versions.yml", emit: versions

    script:
    // A single-file input can arrive unwrapped rather than as a list, so
    // normalise before indexing.
    def staged = bestguess_files instanceof List ? bestguess_files : [bestguess_files]
    // The staged *relative* path ("1/R1_bestguess_G.txt", ...) is what the
    // script below has to read: with `stageAs: "?/*"` above, every file's
    // bare name is the same string for every sample.
    // Written one `printf` per row rather than interpolated into a single
    // heredoc: Nextflow strips only the *common* leading indentation from the
    // script block, so a multi-line interpolated value (i.e. any run with more
    // than one WGS sample) drops that common indent to zero and leaves both
    // the heredoc's first line and its terminator indented - the terminator
    // then never matches, the heredoc swallows the rest of the script, and the
    // first row's sample_id keeps a 4-space prefix. Per-row printf with each
    // field separately quoted is indentation-proof.
    def manifest = (0..<sample_ids.size())
        .collect { i -> "printf '%s\\t%s\\n' '${sample_ids[i]}' '${staged[i]}' >> hlala_manifest.tsv" }
        .join('\n    ')
    """
    : > hlala_manifest.tsv
    ${manifest}

    printf "sample_id\\tLocus\\tHLA_allele\\n" > HLA-LA_combined.tsv
    sort -t \$'\\t' -k1,1 hlala_manifest.tsv | while IFS=\$'\\t' read -r sample_id bestguess_file; do
        tail -n +2 "\${bestguess_file}" \\
            | awk -F '\\t' -v sample_id="\${sample_id}" 'NF >= 3 && \$3 != "" { print sample_id "\\t" \$1 "\\t" \$3 }'
    done >> HLA-LA_combined.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        HLA-LA-combine: "local"
    END_VERSIONS
    """
}
