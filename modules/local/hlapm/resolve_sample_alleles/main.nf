process HLAPM_RESOLVE_SAMPLE_ALLELES {
    tag "hlapm_resolve_sample_alleles"
    label 'process_single'

    publishDir "${params.outdir}/hlapm/star_align",
        mode: params.publish_dir_mode,
        // Unlike HLAPM_LIST_STAR_TARGETS's internal unique_alleles/ copies,
        // this table is the human-facing "which alleles get aligned for
        // which RNA sample" summary requested for QA/testing, so it is
        // published unconditionally/visibly.
        saveAs: { filename -> filename.equals('versions.yml') ? null : filename }

    input:
    path sample_alleles_csv
    path sample_key_csv

    output:
    path "rna_sample_alleles.csv", emit: rna_sample_alleles_csv
    path "versions.yml",           emit: versions

    script:
    """
    set -euo pipefail

    echo "rna_id,sample,allele,allele_key" > rna_sample_alleles.csv

    declare -A wgs_to_rna

    # Build a WGS individual -> RNA sample id(s) mapping from --sample_key.
    # One row per RNA sample that has a matched WGS sample (bin/call_hla_consensus.py's
    # load_rna_wgs_key() docstring) - a WGS individual can therefore be
    # matched by more than one RNA sample, in which case it accumulates a
    # space-separated list of rna ids here.
    # The `|| [[ -n "\${rnaseq_sample_id}" ]]` guard is required because
    # --sample_key is a user-supplied file: `read` returns non-zero on a
    # final line with no trailing newline, which would otherwise make `while`
    # silently skip processing that last row entirely (a classic bash
    # gotcha) instead of just failing to find a trailing newline.
    while IFS=, read -r rnaseq_sample_id wgs_sample_id || [[ -n "\${rnaseq_sample_id}" ]]; do
        [[ "\${rnaseq_sample_id}" == "rnaseq_sample_id" ]] && continue
        if [[ -z "\${wgs_to_rna[\${wgs_sample_id}]:-}" ]]; then
            wgs_to_rna[\${wgs_sample_id}]="\${rnaseq_sample_id}"
        else
            wgs_to_rna[\${wgs_sample_id}]="\${wgs_to_rna[\${wgs_sample_id}]} \${rnaseq_sample_id}"
        fi
    done < <(tail -n +2 "${sample_key_csv}")

    # sample_alleles.csv's "sample" column is keyed by HLA_CONSENSUS's
    # grouping id: the WGS individual_ID for WGS-backed individuals, or a
    # synthetic RNA_ONLY:<rna_id> token otherwise (bin/call_hla_consensus.py).
    # Resolve every row to a real RNA sample id: RNA_ONLY: rows resolve by
    # prefix-stripping alone; all other rows broadcast-join against every RNA
    # sample --sample_key matches to that WGS individual (not collapsed to
    # one - an individual matched to N RNA samples gets its allele set
    # aligned against each of those N samples' own reads).
    # Same trailing-newline guard as above - sample_alleles.csv is generated
    # by HLAPM_LIST_STAR_TARGETS via `>>` redirection, which likewise does
    # not guarantee a trailing newline after its last row.
    while IFS=, read -r sample allele allele_key || [[ -n "\${sample}" ]]; do
        if [[ "\${sample}" == RNA_ONLY:* ]]; then
            rna_id="\${sample#RNA_ONLY:}"
            echo "\${rna_id},\${sample},\${allele},\${allele_key}" >> rna_sample_alleles.csv
        else
            rna_ids="\${wgs_to_rna[\${sample}]:-}"
            if [[ -z "\${rna_ids}" ]]; then
                echo "ERROR: no RNA sample in --sample_key matched WGS individual '\${sample}' (from sample_alleles.csv)" >&2
                exit 1
            fi
            for rna_id in \${rna_ids}; do
                echo "\${rna_id},\${sample},\${allele},\${allele_key}" >> rna_sample_alleles.csv
            done
        fi
    done < <(tail -n +2 "${sample_alleles_csv}")

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bash: \$(bash --version | head -n1 | sed 's/^GNU bash, version //; s/ .*//')
    END_VERSIONS
    """
}
