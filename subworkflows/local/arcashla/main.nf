include { ARCASHLA_EXTRACT } from '../../../modules/local/arcashla/extract'
include { ARCASHLA_VALIDATE_FASTQ } from '../../../modules/local/arcashla/validate'
include { ARCASHLA_GENOTYPE } from '../../../modules/local/arcashla/genotype'
include { ARCASHLA_COMBINE } from '../../../modules/local/arcashla/combine'

workflow ARCASHLA {

    take:
    ch_rna_samplesheet

    main:

    ARCASHLA_EXTRACT(ch_rna_samplesheet)

    ch_extracted_reads = ARCASHLA_EXTRACT.out.reads
        .map { meta, read1, read2 -> [ meta, [ read1, read2 ] ] }

    ARCASHLA_VALIDATE_FASTQ(ch_extracted_reads)

    ARCASHLA_GENOTYPE(ARCASHLA_VALIDATE_FASTQ.out.reads)

    ch_genotype_json = ARCASHLA_GENOTYPE.out.genotype
        .map { meta, genotype_json -> [ meta.id, genotype_json ] }
        .collect(flat: false)
        .map { rows ->
            [
                rows.collect { row -> row[0] },
                rows.collect { row -> row[1] }
            ]
        }

    ARCASHLA_COMBINE(ch_genotype_json)

    ch_versions = ARCASHLA_EXTRACT.out.versions
        .mix(ARCASHLA_VALIDATE_FASTQ.out.versions)
        .mix(ARCASHLA_GENOTYPE.out.versions)
        .mix(ARCASHLA_COMBINE.out.versions)

    emit:
    reads             = ARCASHLA_VALIDATE_FASTQ.out.reads
    validation_logs   = ARCASHLA_VALIDATE_FASTQ.out.logs
    genotypes         = ARCASHLA_GENOTYPE.out.genotype
    genotype_logs     = ARCASHLA_GENOTYPE.out.log
    combined_genotype = ARCASHLA_COMBINE.out.csv
    hla_region_bam    = ARCASHLA_EXTRACT.out.bam // channel: [ val(meta), path("*.mhc.namesort.bam") ], meta.id == rna_id - HLA-region-restricted, primary-alignment-only, name-sorted BAM (pre-FASTQ-conversion intermediate), not the reads/FASTQ output above
    versions          = ch_versions
}
