include { SUBREAD_FEATURECOUNTS } from '../../../modules/nf-core/subread/featurecounts'

workflow COUNTS_COMMONREF {

    take:
    ch_rna_samplesheet // channel: [ val(meta), path(bam), path(bai), [ path(unpaired_r1), path(unpaired_r2) ] ], meta.id == rna_id, the same channel passed to ARCASHLA
    ch_gtf             // value channel: path(gtf), from --gtf

    main:

    // SUBREAD_FEATURECOUNTS's input signature is a single combined tuple
    // [ val(meta), path(bams), path(annotation) ] - no BAI slot, so bai is
    // dropped here; unpaired_reads is also dropped as it is irrelevant to
    // whole-genome counting against the sample's already-aligned BAM.
    // params.rnaseq_strandedness (pipeline-wide, not per-sample) is merged
    // into meta here since the module reads meta.strandedness directly.
    ch_bam = ch_rna_samplesheet
        .map { meta, bam, bai, unpaired_reads -> [ meta + [ strandedness: params.rnaseq_strandedness ], bam ] }

    // ch_gtf is already a value channel (a single whole-genome reference GTF
    // shared across every RNA sample), so `combine` broadcasts it to every
    // per-sample SUBREAD_FEATURECOUNTS call without needing an extra
    // `.first()`.
    SUBREAD_FEATURECOUNTS(ch_bam.combine(ch_gtf))

    emit:
    gene_counts = SUBREAD_FEATURECOUNTS.out.counts  // channel: [ val(meta), path("*featureCounts.tsv") ], meta.id == rna_id
    summary     = SUBREAD_FEATURECOUNTS.out.summary // channel: [ val(meta), path("*featureCounts.tsv.summary") ], meta.id == rna_id
    // SUBREAD_FEATURECOUNTS reports its own version via the topic-based
    // `versions` channel (like STAR_ALIGN/STAR_GENOMEGENERATE/SAMTOOLS_SORT
    // elsewhere in this pipeline), collected automatically at the top-level
    // workflow rather than mixed in here - no versions emit needed.
}
