include { HLA_READCOUNT_RECONCILE_DIFF } from '../../../modules/local/hla_readcount_reconcile'

workflow HLA_READCOUNT_RECONCILE {

    take:
    ch_read_gene_assignments // channel: [ val(meta), path("*.rnaseq_featurecounts.tsv") ], meta.id == rna_id, from COUNTS_COMMONREF_HLA.out.read_gene_assignments
    ch_edit_distance         // channel: [ val(meta), path("*.edit_distance.tsv") ], meta.id == rna_id, from HLAPM_STAR_QUANTIFY.out.edit_distance
    ch_gtf                   // value channel: path(gtf), from --gtf - the same whole-genome GTF COUNTS_COMMONREF/COUNTS_COMMONREF_HLA already use

    main:

    // Both inputs are guaranteed at most one row per rna_id
    // (COUNTS_COMMONREF_HLA_REFORMAT and HLAPM_QUANTIFY_READS both run once
    // per RNA sample), so a plain `.join()` - unlike HLAPM_STAR_ALIGN's own
    // `combine(by: 0)`, needed there because its left channel can have
    // multiple rows per key - is both sufficient and exactly the desired
    // "only compare samples that have both tables" semantics: an RNA sample
    // not resolved through --sample_key/HLApm to at least one personalized
    // allele simply has no ch_edit_distance row and is silently dropped
    // here (an expected inner-join outcome, not an error).
    ch_fc_by_id = ch_read_gene_assignments.map { meta, tsv -> [ meta.id, tsv ] }
    ch_pers_by_id = ch_edit_distance.map { meta, tsv -> [ meta.id, tsv ] }

    // Reconstructs a clean [id: rna_id] meta, discarding the fc side's extra
    // single_end/strandedness keys (not meaningful to this step).
    ch_joined = ch_fc_by_id
        .join(ch_pers_by_id)
        .map { rna_id, fc_tsv, pers_tsv -> [ [ id: rna_id ], fc_tsv, pers_tsv ] }

    HLA_READCOUNT_RECONCILE_DIFF(ch_joined, ch_gtf)

    ch_versions = HLA_READCOUNT_RECONCILE_DIFF.out.versions

    emit:
    read_count_diff              = HLA_READCOUNT_RECONCILE_DIFF.out.read_count_diff // channel: [ val(meta), path("*.hla_readcount_reconcile.tsv") ], meta.id == rna_id
    gene_id_resolution_warnings  = HLA_READCOUNT_RECONCILE_DIFF.out.gene_id_resolution_warnings // channel: [ val(meta), path("*.gene_id_resolution_warnings.tsv") ], meta.id == rna_id
    versions                     = ch_versions // channel: [ path(versions.yml) ]
}
