include { ARCASHLA_EXTRACT } from '../../../modules/local/arcashla/extract'
include { ARCASHLA_VALIDATE_FASTQ } from '../../../modules/local/arcashla/validate'

workflow ARCASHLA {

    take:
    ch_rna_samplesheet

    main:

    ARCASHLA_EXTRACT(ch_rna_samplesheet)

    ch_extracted_reads = ARCASHLA_EXTRACT.out.reads
        .map { meta, read1, read2 -> [ meta, [ read1, read2 ] ] }

    ARCASHLA_VALIDATE_FASTQ(ch_extracted_reads)

    ch_versions = ARCASHLA_EXTRACT.out.versions.mix(ARCASHLA_VALIDATE_FASTQ.out.versions)

    emit:
    reads           = ARCASHLA_VALIDATE_FASTQ.out.reads
    validation_logs = ARCASHLA_VALIDATE_FASTQ.out.logs
    versions        = ch_versions
}
