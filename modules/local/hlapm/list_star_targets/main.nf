process HLAPM_LIST_STAR_TARGETS {
    tag "hlapm_list_star_targets"
    label 'process_single'

    publishDir "${params.outdir}/hlapm/star_index_targets",
        mode: params.publish_dir_mode,
        // publishDir's saveAs receives the top-level published name for a
        // directory-type output (here literally "unique_alleles", not a
        // per-contained-file path) - the deduplicated fasta/gtf copies are
        // internal plumbing for STAR_GENOMEGENERATE, not a pipeline-visible
        // output, so the whole directory is excluded from publishing.
        saveAs: { filename -> (filename == 'versions.yml' || filename == 'unique_alleles') ? null : filename }

    input:
    path personalized_ref, stageAs: 'personalized_ref_in'

    output:
    path "unique_alleles.csv", emit: unique_alleles_csv
    path "sample_alleles.csv", emit: sample_alleles_csv
    path "unique_alleles",     emit: unique_alleles_dir
    path "versions.yml",       emit: versions

    script:
    """
    set -euo pipefail

    mkdir -p unique_alleles

    echo "allele_key,representative_name,fasta,gtf" > unique_alleles.csv
    echo "sample,allele,allele_key" > sample_alleles.csv

    declare -A hash_to_key

    # The set of alleles indexed is discovered by recursively scanning for
    # *.fa files anywhere under the personalized-reference tree and pairing
    # each with its co-located *.gtf - not from any consensus or
    # HLApm-input TSV, and without assuming a fixed directory nesting depth.
    # HLApm's own bulkRNA_build_personalized_HLA_ref() nests every
    # individual's allele files one level deeper than the output_directory
    # it is given (under an extra "out/" it creates itself), so the real
    # per-individual directories are not always direct children of the
    # staged input; the immediate parent directory of each *.fa is treated
    # as the sample name, whatever its depth. Non-.fa files anywhere in the
    # tree (e.g. mask_these_genes.bed) never match the glob below and are
    # therefore always ignored.
    while IFS= read -r fa; do
        sample_dir=\$(dirname "\${fa}")
        sample=\$(basename "\${sample_dir}")
        allele=\$(basename "\${fa}" .fa)
        gtf="\${sample_dir}/\${allele}.gtf"
        if [[ ! -f "\${gtf}" ]]; then
            echo "ERROR: no matching .gtf for \${fa} (expected \${gtf})" >&2
            exit 1
        fi

        hash=\$(cat "\${fa}" "\${gtf}" | sha256sum | cut -d' ' -f1)

        if [[ -z "\${hash_to_key[\${hash}]:-}" ]]; then
            allele_key="\${allele}__\${hash:0:8}"
            hash_to_key[\${hash}]="\${allele_key}"
            cp "\${fa}"  "unique_alleles/\${allele_key}.fa"
            cp "\${gtf}" "unique_alleles/\${allele_key}.gtf"
            echo "\${allele_key},\${allele},\${allele_key}.fa,\${allele_key}.gtf" >> unique_alleles.csv
        fi

        echo "\${sample},\${allele},\${hash_to_key[\${hash}]}" >> sample_alleles.csv
    done < <(find -L personalized_ref_in -type f -name '*.fa' | sort)

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bash: \$(bash --version | head -n1 | sed 's/^GNU bash, version //; s/ .*//')
    END_VERSIONS
    """
}
