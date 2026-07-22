include { ARCASHLA_EXTRACT } from '../../../modules/local/arcashla/extract'

workflow ARCASHLA {

    take:
    ch_rna_samplesheet

    main:

    ARCASHLA_EXTRACT(ch_rna_samplesheet)

    ch_reads = ARCASHLA_EXTRACT.out.reads
        .map { meta, read1, read2 -> [ meta, [ read1, read2 ] ] }

    emit:
    reads    = ch_reads
    versions = ARCASHLA_EXTRACT.out.versions
}
