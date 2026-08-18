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
include { HLA_CONSENSUS          } from '../modules/local/hla_consensus'
include { HLAPM                  } from '../subworkflows/local/hlapm'
include { HLAPM_STAR_INDEX       } from '../subworkflows/local/hlapm_star_index'
include { HLAPM_STAR_ALIGN       } from '../subworkflows/local/hlapm_star_align'
include { HLAPM_STAR_QUANTIFY    } from '../subworkflows/local/hlapm_star_quantify'
include { COUNTS_COMMONREF       } from '../subworkflows/local/counts_commonref'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow HLARNASEQ {

    take:
    ch_rna_samplesheet // channel: RNA samplesheet read in from --rna_samples
    ch_wgs_samplesheet // channel: WGS samplesheet read in from --wgs_samples
    ch_sample_key      // channel: RNA/WGS sample key read in from --sample_key
    main:

    ch_versions = channel.empty()
    ch_hlala_combined = channel.empty()
    ch_arcashla_reads = channel.empty()
    ch_arcashla_validation_logs = channel.empty()
    ch_arcashla_genotypes = channel.empty()
    ch_arcashla_genotype_logs = channel.empty()
    ch_arcashla_combined_genotype = channel.empty()
    ch_hla_consensus_summary = channel.empty()
    ch_hla_consensus_key = channel.empty()
    ch_hlapm_personalized_ref = channel.empty()
    ch_hlapm_star_index = channel.empty()
    ch_hlapm_star_index_gtf = channel.empty()
    ch_hlapm_star_index_sample_alleles = channel.empty()
    ch_hlapm_star_align_bam = channel.empty()
    ch_hlapm_star_align_log_final = channel.empty()
    ch_hlapm_star_align_rna_sample_alleles = channel.empty()
    ch_hlapm_edit_distance = channel.empty()
    ch_hlapm_gene_summary = channel.empty()
    ch_counts_commonref_gene_counts = channel.empty()
    ch_counts_commonref_summary = channel.empty()

    if (params.rna_samples) {
        ARCASHLA(ch_rna_samplesheet)
        ch_versions = ch_versions.mix(ARCASHLA.out.versions)
        ch_arcashla_reads = ARCASHLA.out.reads
        ch_arcashla_validation_logs = ARCASHLA.out.validation_logs
        ch_arcashla_genotypes = ARCASHLA.out.genotypes
        ch_arcashla_genotype_logs = ARCASHLA.out.genotype_logs
        ch_arcashla_combined_genotype = ARCASHLA.out.combined_genotype

        // Runs on the sample's original whole-genome BAM (--rna_samples'
        // bam/bai columns), independent of --sample_key/HLApm - iteration 1
        // of "hijack original count matrix" (see docs/output.md).
        // SUBREAD_FEATURECOUNTS reports its own version via the topic-based
        // versions channel (like STAR_ALIGN/STAR_GENOMEGENERATE/SAMTOOLS_SORT
        // elsewhere in this pipeline), collected automatically below -
        // COUNTS_COMMONREF has no other module and so emits no versions
        // channel of its own to mix in here.
        ch_gtf = Channel.value(file(params.gtf))
        COUNTS_COMMONREF(ch_rna_samplesheet, ch_gtf)
        ch_counts_commonref_gene_counts = COUNTS_COMMONREF.out.gene_counts
        ch_counts_commonref_summary = COUNTS_COMMONREF.out.summary
    }

    if (params.wgs_samples) {
        HLALA(ch_wgs_samplesheet)
        ch_versions = ch_versions.mix(HLALA.out.versions)
        ch_hlala_combined = HLALA.out.combined_csv
    } else {
        ch_hlala_combined = Channel.fromPath("${projectDir}/assets/NO_WGS_HLALA_COMBINED.tsv")
    }

    if (params.rna_samples && params.sample_key) {
        ch_rna_excluded_samples = params.rna_excluded_samples
            ? Channel.fromPath(params.rna_excluded_samples)
            : Channel.fromPath("${projectDir}/assets/NO_FILE")
        ch_wgs_excluded_samples = params.wgs_excluded_samples
            ? Channel.fromPath(params.wgs_excluded_samples)
            : Channel.fromPath("${projectDir}/assets/NO_FILE")

        HLA_CONSENSUS(
            ch_arcashla_combined_genotype,
            ch_hlala_combined,
            ch_sample_key,
            ch_rna_excluded_samples,
            ch_wgs_excluded_samples
        )
        ch_versions = ch_versions.mix(HLA_CONSENSUS.out.versions)
        ch_hla_consensus_summary = HLA_CONSENSUS.out.summary
        ch_hla_consensus_key = HLA_CONSENSUS.out.consensus

        HLAPM(ch_hla_consensus_key)
        ch_versions = ch_versions.mix(HLAPM.out.versions)
        ch_hlapm_personalized_ref = HLAPM.out.personalized_ref

        HLAPM_STAR_INDEX(ch_hlapm_personalized_ref)
        ch_versions = ch_versions.mix(HLAPM_STAR_INDEX.out.versions)
        ch_hlapm_star_index = HLAPM_STAR_INDEX.out.index
        ch_hlapm_star_index_gtf = HLAPM_STAR_INDEX.out.gtf
        ch_hlapm_star_index_sample_alleles = HLAPM_STAR_INDEX.out.sample_alleles

        HLAPM_STAR_ALIGN(
            ch_hlapm_star_index_sample_alleles,
            ch_hlapm_star_index,
            ch_hlapm_star_index_gtf,
            ch_arcashla_reads,
            ch_sample_key
        )
        ch_versions = ch_versions.mix(HLAPM_STAR_ALIGN.out.versions)
        ch_hlapm_star_align_bam = HLAPM_STAR_ALIGN.out.bam_sorted
        ch_hlapm_star_align_log_final = HLAPM_STAR_ALIGN.out.log_final
        ch_hlapm_star_align_rna_sample_alleles = HLAPM_STAR_ALIGN.out.rna_sample_alleles

        HLAPM_STAR_QUANTIFY(ch_hlapm_star_align_bam, ch_hlapm_star_index_gtf)
        ch_versions = ch_versions.mix(HLAPM_STAR_QUANTIFY.out.versions)
        ch_hlapm_edit_distance = HLAPM_STAR_QUANTIFY.out.edit_distance
        ch_hlapm_gene_summary = HLAPM_STAR_QUANTIFY.out.gene_summary
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
    hlala_combined = ch_hlala_combined           // channel: [ path(HLA-LA_combined.tsv) ]
    arcashla_reads = ch_arcashla_reads           // channel: [ val(meta), [ path(read1), path(read2) ] ]
    arcashla_validation_logs = ch_arcashla_validation_logs // channel: [ val(meta), path(validatefastq.log) ]
    arcashla_genotypes = ch_arcashla_genotypes   // channel: [ val(meta), path(genotype.json) ]
    arcashla_genotype_logs = ch_arcashla_genotype_logs // channel: [ val(meta), path(genotype.log) ]
    arcashla_combined_genotype = ch_arcashla_combined_genotype // channel: [ path(arcasHLA_combined.csv) ]
    hla_consensus_summary = ch_hla_consensus_summary // channel: [ path(hla_consensus.rna_wgs_rna-hla_with_consensus.tsv) ]
    hla_consensus_key = ch_hla_consensus_key // channel: [ path(hla_consensus.rna_wgs_hla_consensus.tsv) ]
    hlapm_personalized_ref = ch_hlapm_personalized_ref // channel: [ path("out") ]
    hlapm_star_index = ch_hlapm_star_index // channel: [ val(meta), path("star") ], meta.id == allele_key
    hlapm_star_index_gtf = ch_hlapm_star_index_gtf // channel: [ val(meta), path(gtf) ], meta.id == allele_key
    hlapm_star_index_sample_alleles = ch_hlapm_star_index_sample_alleles // channel: [ path("sample_alleles.csv") ]
    hlapm_star_align_bam = ch_hlapm_star_align_bam // channel: [ val(meta), path("*.sortedByCoord.out.bam") ]
    hlapm_star_align_log_final = ch_hlapm_star_align_log_final // channel: [ val(meta), path("*.Log.final.out") ]
    hlapm_star_align_rna_sample_alleles = ch_hlapm_star_align_rna_sample_alleles // channel: [ path("rna_sample_alleles.csv") ]
    hlapm_edit_distance = ch_hlapm_edit_distance // channel: [ val(meta), path("*.edit_distance.tsv") ], meta.id == rna_id
    hlapm_gene_summary = ch_hlapm_gene_summary // channel: [ val(meta), path("*.HLA_gene_summary.tsv") ], meta.id == rna_id
    counts_commonref_gene_counts = ch_counts_commonref_gene_counts // channel: [ val(meta), path("*featureCounts.tsv") ], meta.id == rna_id
    counts_commonref_summary = ch_counts_commonref_summary // channel: [ val(meta), path("*featureCounts.tsv.summary") ], meta.id == rna_id

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
