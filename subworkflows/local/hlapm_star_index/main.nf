include { HLAPM_LIST_STAR_TARGETS } from '../../../modules/local/hlapm/list_star_targets'
include { STAR_GENOMEGENERATE     } from '../../../modules/nf-core/star/genomegenerate'

workflow HLAPM_STAR_INDEX {

    take:
    ch_personalized_ref // channel: [ path("out") ]

    main:

    HLAPM_LIST_STAR_TARGETS(ch_personalized_ref)

    // One row per distinct allele content hash (fasta+gtf), deduplicated
    // across every individual that shares that exact sequence.
    ch_targets = HLAPM_LIST_STAR_TARGETS.out.unique_alleles_csv
        .splitCsv(header: true)
        .combine(HLAPM_LIST_STAR_TARGETS.out.unique_alleles_dir)
        .map { row, dir ->
            def meta = [ id: row.allele_key ]
            [ meta, dir.resolve(row.fasta), dir.resolve(row.gtf) ]
        }

    ch_fasta = ch_targets.map { meta, fasta, gtf -> [ meta, fasta ] }
    ch_gtf   = ch_targets.map { meta, fasta, gtf -> [ meta, gtf   ] }

    STAR_GENOMEGENERATE(ch_fasta, ch_gtf)

    ch_versions = HLAPM_LIST_STAR_TARGETS.out.versions

    emit:
    index          = STAR_GENOMEGENERATE.out.index               // channel: [ val(meta), path("star") ], meta.id == allele_key
    sample_alleles = HLAPM_LIST_STAR_TARGETS.out.sample_alleles_csv // channel: [ path("sample_alleles.csv") ]
    versions       = ch_versions
}
