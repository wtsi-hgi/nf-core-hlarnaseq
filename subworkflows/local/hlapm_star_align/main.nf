include { HLAPM_RESOLVE_SAMPLE_ALLELES } from '../../../modules/local/hlapm/resolve_sample_alleles'
include { STAR_ALIGN                   } from '../../../modules/nf-core/star/align'

workflow HLAPM_STAR_ALIGN {

    take:
    ch_sample_alleles // channel: [ path("sample_alleles.csv") ], from HLAPM_STAR_INDEX.out.sample_alleles
    ch_index          // channel: [ val(meta), path("star") ], meta.id == allele_key, from HLAPM_STAR_INDEX.out.index
    ch_gtf            // channel: [ val(meta), path(gtf) ], meta.id == allele_key, from HLAPM_STAR_INDEX.out.gtf
    ch_reads          // channel: [ val(meta), [ path(read1), path(read2) ] ], meta.id == rna_id, from ch_arcashla_reads
    ch_sample_key     // channel: [ path(sample_key.csv) ], the raw --sample_key manifest

    main:

    HLAPM_RESOLVE_SAMPLE_ALLELES(ch_sample_alleles, ch_sample_key)

    // One row per resolved (rna_id, sample, allele, allele_key) - already
    // bridged to real RNA sample ids by HLAPM_RESOLVE_SAMPLE_ALLELES, so no
    // further WGS-individual/RNA-id reconciliation is needed here.
    ch_resolved = HLAPM_RESOLVE_SAMPLE_ALLELES.out.rna_sample_alleles_csv
        .splitCsv(header: true)
        .map { row -> [ row.allele_key, row.rna_id, row.sample, row.allele ] }

    ch_index_by_key = ch_index.map { meta, star -> [ meta.id, star ] }
    ch_gtf_by_key   = ch_gtf.map   { meta, gtf  -> [ meta.id, gtf  ] }

    // Join the resolved manifest against the shared per-allele index/gtf
    // (built once per distinct allele content hash by HLAPM_STAR_INDEX,
    // keyed by allele_key). Nextflow's `join` operator silently drops
    // duplicate-key items on the left channel (keeping only the first
    // match per key), which would wrongly collapse e.g. two RNA samples
    // sharing the same allele_key down to one job - `combine(by: 0)`
    // performs a proper broadcast join instead, pairing every left item
    // with its matching right item(s).
    ch_with_index_gtf = ch_resolved
        .combine(ch_index_by_key, by: 0) // by allele_key (index 0): [ allele_key, rna_id, sample, allele, star ]
        .combine(ch_gtf_by_key, by: 0)   // by allele_key (index 0): [ allele_key, rna_id, sample, allele, star, gtf ]

    // ...then against each RNA sample's arcasHLA MHC-extracted reads (keyed
    // by rna_id), broadcasting a sample's single read pair across every
    // allele row it has - a sample with N personalized alleles produces N
    // separate STAR_ALIGN jobs, each reusing the same reads against a
    // different single-allele index. Same duplicate-key caveat as above:
    // `combine(by: 0)`, not `join`, so a multi-allele sample's several rows
    // (which all share the same rna_id key here) each still get matched.
    ch_reads_by_id = ch_reads.map { meta, reads -> [ meta.id, reads ] }

    ch_star_align_input = ch_with_index_gtf
        .map { allele_key, rna_id, sample, allele, star, gtf -> [ rna_id, allele_key, sample, allele, star, gtf ] }
        .combine(ch_reads_by_id, by: 0) // by rna_id (index 0): [ rna_id, allele_key, sample, allele, star, gtf, reads ]
        .map { rna_id, allele_key, sample, allele, star, gtf, reads ->
            // meta.id is unique per (rna_id, allele_key) pair - STAR_ALIGN
            // uses it both as its `tag` and as its output filename prefix.
            def meta = [
                id: "${rna_id}.${allele_key}",
                single_end: false,
                rna_id: rna_id,
                sample: sample,
                allele: allele,
                allele_key: allele_key
            ]
            [ meta, reads, star, gtf ]
        }

    ch_reads_in = ch_star_align_input.map { meta, reads, star, gtf -> [ meta, reads ] }
    ch_index_in = ch_star_align_input.map { meta, reads, star, gtf -> [ meta, star  ] }
    ch_gtf_in   = ch_star_align_input.map { meta, reads, star, gtf -> [ meta, gtf   ] }

    STAR_ALIGN(ch_reads_in, ch_index_in, ch_gtf_in, false)

    ch_versions = HLAPM_RESOLVE_SAMPLE_ALLELES.out.versions

    emit:
    bam_sorted         = STAR_ALIGN.out.bam_sorted                       // channel: [ val(meta), path("*.sortedByCoord.out.bam") ]
    log_final          = STAR_ALIGN.out.log_final                       // channel: [ val(meta), path("*.Log.final.out") ]
    rna_sample_alleles = HLAPM_RESOLVE_SAMPLE_ALLELES.out.rna_sample_alleles_csv // channel: [ path("rna_sample_alleles.csv") ]
    versions           = ch_versions
}
