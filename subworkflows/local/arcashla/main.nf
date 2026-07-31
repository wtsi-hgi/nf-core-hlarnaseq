include { ARCASHLA_EXTRACT } from '../../../modules/local/arcashla/extract'
include { ARCASHLA_VALIDATE_FASTQ } from '../../../modules/local/arcashla/validate'
include { ARCASHLA_GENOTYPE } from '../../../modules/local/arcashla/genotype'

workflow ARCASHLA {

    take:
    ch_rna_samplesheet

    main:

    ARCASHLA_EXTRACT(ch_rna_samplesheet)

    ch_extracted_reads = ARCASHLA_EXTRACT.out.reads
        .map { meta, read1, read2 -> [ meta, [ read1, read2 ] ] }

    ARCASHLA_VALIDATE_FASTQ(ch_extracted_reads)

    ARCASHLA_GENOTYPE(ARCASHLA_VALIDATE_FASTQ.out.reads)

    ch_versions = ARCASHLA_EXTRACT.out.versions
        .mix(ARCASHLA_VALIDATE_FASTQ.out.versions)
        .mix(ARCASHLA_GENOTYPE.out.versions)

    emit:
    reads           = ARCASHLA_VALIDATE_FASTQ.out.reads
    validation_logs = ARCASHLA_VALIDATE_FASTQ.out.logs
    genotypes       = ARCASHLA_GENOTYPE.out.genotype
    genotype_logs   = ARCASHLA_GENOTYPE.out.log
    versions        = ch_versions
}
