include { SUBREAD_FEATURECOUNTS as SUBREAD_FEATURECOUNTS_HLA } from '../../../modules/nf-core/subread/featurecounts'
include { COUNTS_COMMONREF_HLA_REFORMAT                       } from '../../../modules/local/counts_commonref_hla'

workflow COUNTS_COMMONREF_HLA {

    take:
    ch_hla_region_bam // channel: [ val(meta), path("*.mhc.namesort.bam") ], meta.id == rna_id, from ARCASHLA.out.hla_region_bam - the HLA-region-restricted, primary-alignment-only, name-sorted BAM (ARCASHLA_EXTRACT's intermediate, not its reads/FASTQ output)
    ch_gtf            // value channel: path(gtf), from --gtf - the same whole-genome GTF COUNTS_COMMONREF already uses

    main:

    // params.rnaseq_strandedness (pipeline-wide, not per-sample) is merged
    // into meta here since SUBREAD_FEATURECOUNTS_HLA - an alias of the same
    // vendored module COUNTS_COMMONREF uses - also reads meta.strandedness
    // directly. Matches COUNTS_COMMONREF's own merge exactly.
    ch_bam = ch_hla_region_bam
        .map { meta, bam -> [ meta + [ strandedness: params.rnaseq_strandedness ], bam ] }

    // ch_gtf is already a value channel, so `combine` broadcasts it to every
    // per-sample SUBREAD_FEATURECOUNTS_HLA call without needing an extra
    // `.first()` - same as COUNTS_COMMONREF's own call.
    SUBREAD_FEATURECOUNTS_HLA(ch_bam.combine(ch_gtf))

    // COUNTS_COMMONREF_HLA_REFORMAT takes the per-sample reannotated `-R BAM`
    // output as a tuple, and the shared GTF as a separate, directly-broadcast
    // value-channel input (no `.combine()` needed here) - matching the
    // HLAPM_QUANTIFY_READS/HLAPM_COMBINE_GTF.out.gtf.first() precedent for a
    // per-sample-tuple-plus-broadcast-value-channel process signature.
    COUNTS_COMMONREF_HLA_REFORMAT(SUBREAD_FEATURECOUNTS_HLA.out.bam, ch_gtf)

    // SUBREAD_FEATURECOUNTS_HLA reports its own version via the topic-based
    // `versions` channel (like COUNTS_COMMONREF's own SUBREAD_FEATURECOUNTS
    // call), collected automatically at the top-level workflow - no manual
    // mixing needed for it. COUNTS_COMMONREF_HLA_REFORMAT emits a
    // conventional versions.yml path output instead (matching
    // HLA_CONSENSUS/HLAPM_COMBINE_GTF's own pattern), so it is mixed in here,
    // same as HLAPM_STAR_QUANTIFY's own versions emit.
    ch_versions = COUNTS_COMMONREF_HLA_REFORMAT.out.versions

    emit:
    read_gene_assignments = COUNTS_COMMONREF_HLA_REFORMAT.out.read_gene_assignments // channel: [ val(meta), path("*.rnaseq_featurecounts.tsv") ], meta.id == rna_id
    versions              = ch_versions // channel: [ path(versions.yml) ]
}
