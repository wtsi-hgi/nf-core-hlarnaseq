include { HIBAG_PREDICT } from '../../../modules/local/hibag/predict'
include { HIBAG_COMBINE } from '../../../modules/local/hibag/combine'

//
// Call HLA alleles from SNP-array genotypes with HIBAG.
//
// This subworkflow is the alternative to HLALA: it emits the same
// `combined_csv` contract (a `sample_id/Locus/HLA_allele` TSV), so
// workflows/hlarnaseq.nf can feed either one into HLA_CONSENSUS unchanged.
//
workflow HIBAG {

    take:
    ch_array_samplesheet // channel: [ val(meta), path(bed), path(bim), path(fam) ]

    main:

    // One pre-fit model file is shared by every array dataset, so it is a
    // value channel broadcast to each HIBAG_PREDICT task.
    ch_model = channel.value(file(params.hibag_model, checkIfExists: true))

    HIBAG_PREDICT(ch_array_samplesheet, ch_model)

    // Collected flat: HIBAG_COMBINE takes only the file list, because each
    // per-dataset file already carries its sample IDs in column 1 (they come
    // from the PLINK .fam, not from the samplesheet row label).
    ch_calls = HIBAG_PREDICT.out.calls
        .map { _meta, calls -> calls }
        .collect()

    HIBAG_COMBINE(ch_calls)

    ch_versions = HIBAG_PREDICT.out.versions
        .mix(HIBAG_COMBINE.out.versions)

    emit:
    combined_csv = HIBAG_COMBINE.out.csv
    calls        = HIBAG_PREDICT.out.calls
    posterior    = HIBAG_PREDICT.out.posterior
    versions     = ch_versions
}
