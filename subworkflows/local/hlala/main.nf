include { HLALA_RUN     } from '../../../modules/local/hlala/run'
include { HLALA_COMBINE } from '../../../modules/local/hlala/combine'

workflow HLALA {

    take:
    ch_wgs_samplesheet

    main:

    HLALA_RUN(ch_wgs_samplesheet)

    ch_bestguess_g = HLALA_RUN.out.bestguess_g
        .map { meta, bestguess_g -> [ meta.id, bestguess_g ] }
        .collect()
        .map { rows ->
            [
                rows.collect { row -> row[0] },
                rows.collect { row -> row[1] }
            ]
        }

    HLALA_COMBINE(ch_bestguess_g)

    ch_versions = HLALA_RUN.out.versions.mix(HLALA_COMBINE.out.versions)

    emit:
    combined_csv = HLALA_COMBINE.out.csv
    versions     = ch_versions
}
