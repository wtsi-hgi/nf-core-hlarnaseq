process HIBAG_COMBINE {
    tag "HIBAG_combined"
    label 'process_single'

    publishDir "${params.outdir}/hibag",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    // HIBAG_PREDICT names its output after the samplesheet row, so two rows
    // could in principle collide when staged side by side. `stageAs: "?/*"`
    // gives each file its own numbered subdirectory, as HLALA_COMBINE does.
    path calls_files, stageAs: "?/*"

    output:
    path "HIBAG_combined.tsv", emit: csv
    path "versions.yml", emit: versions

    script:
    // A single-file input can arrive unwrapped rather than as a list.
    def staged = calls_files instanceof List ? calls_files : [calls_files]
    // Joined onto one line: a multi-line interpolated value would break the
    // script block's common-indentation stripping (see HLALA_COMBINE).
    def file_list = staged.collect { "'${it}'" }.join(' ')
    """
    # Header written once, then every per-dataset body concatenated and sorted.
    # This is byte-for-byte the same three-column contract HLALA_COMBINE
    # produces, so call_hla_consensus.py consumes it unchanged.
    printf 'sample_id\\tLocus\\tHLA_allele\\n' > HIBAG_combined.tsv
    tail -q -n +2 ${file_list} \\
        | awk -F '\\t' 'NF >= 3 && \$3 != ""' \\
        | LC_ALL=C sort -t \$'\\t' -k1,1 -k2,2 -k3,3 \\
        >> HIBAG_combined.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        HIBAG-combine: "local"
    END_VERSIONS
    """

    stub:
    """
    printf 'sample_id\\tLocus\\tHLA_allele\\n' > HIBAG_combined.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        HIBAG-combine: "local"
    END_VERSIONS
    """
}
