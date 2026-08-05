include { HLAPM_PREPARE_INPUT } from '../../../modules/local/hlapm/prepare_input'
include { HLAPM_BUILD_REF     } from '../../../modules/local/hlapm/build_ref'

workflow HLAPM {

    take:
    ch_hla_consensus_key // channel: [ path(hla_consensus.rna_wgs_hla_consensus.tsv) ]

    main:

    HLAPM_PREPARE_INPUT(ch_hla_consensus_key)

    HLAPM_BUILD_REF(HLAPM_PREPARE_INPUT.out.sample_tsvs)

    ch_versions = HLAPM_PREPARE_INPUT.out.versions.mix(HLAPM_BUILD_REF.out.versions)

    emit:
    sample_tsvs      = HLAPM_PREPARE_INPUT.out.sample_tsvs // channel: [ path("*.tsv") ]
    personalized_ref = HLAPM_BUILD_REF.out.personalized_ref // channel: [ path("out") ]
    versions         = ch_versions
}
