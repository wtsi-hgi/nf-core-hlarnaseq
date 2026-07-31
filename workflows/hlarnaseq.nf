/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_hlarnaseq_pipeline'
include { HLALA                  } from '../subworkflows/local/hlala'
include { ARCASHLA                } from '../subworkflows/local/arcashla'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow HLARNASEQ {

    take:
    ch_rna_samplesheet // channel: RNA samplesheet read in from --rna_samples
    ch_wgs_samplesheet // channel: WGS samplesheet read in from --wgs_samples
    main:

    ch_versions = channel.empty()
    ch_hlala_combined = channel.empty()
    ch_arcashla_reads = channel.empty()
    ch_arcashla_validation_logs = channel.empty()
    ch_arcashla_genotypes = channel.empty()
    ch_arcashla_genotype_logs = channel.empty()
    ch_arcashla_combined_genotype = channel.empty()

    if (params.rna_samples) {
        ARCASHLA(ch_rna_samplesheet)
        ch_versions = ch_versions.mix(ARCASHLA.out.versions)
        ch_arcashla_reads = ARCASHLA.out.reads
        ch_arcashla_validation_logs = ARCASHLA.out.validation_logs
        ch_arcashla_genotypes = ARCASHLA.out.genotypes
        ch_arcashla_genotype_logs = ARCASHLA.out.genotype_logs
        ch_arcashla_combined_genotype = ARCASHLA.out.combined_genotype
    }

    if (params.wgs_samples) {
        HLALA(ch_wgs_samplesheet)
        ch_versions = ch_versions.mix(HLALA.out.versions)
        ch_hlala_combined = HLALA.out.combined_csv
    }

    //
    // Collate and save software versions
    //
    def topic_versions = Channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'hlarnaseq_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
    hlala_combined = ch_hlala_combined           // channel: [ path(HLA-LA_combined.csv) ]
    arcashla_reads = ch_arcashla_reads           // channel: [ val(meta), [ path(read1), path(read2) ] ]
    arcashla_validation_logs = ch_arcashla_validation_logs // channel: [ val(meta), path(validatefastq.log) ]
    arcashla_genotypes = ch_arcashla_genotypes   // channel: [ val(meta), path(genotype.json) ]
    arcashla_genotype_logs = ch_arcashla_genotype_logs // channel: [ val(meta), path(genotype.log) ]
    arcashla_combined_genotype = ch_arcashla_combined_genotype // channel: [ path(arcasHLA_combined.csv) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
