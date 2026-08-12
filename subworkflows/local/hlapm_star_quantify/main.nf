include { SAMTOOLS_SORT         } from '../../../modules/nf-core/samtools/sort'
include { HLAPM_COMBINE_GTF     } from '../../../modules/local/hlapm/combine_gtf'
include { HLAPM_QUANTIFY_READS  } from '../../../modules/local/hlapm/quantify_reads'

workflow HLAPM_STAR_QUANTIFY {

    take:
    ch_bam_sorted // channel: [ val(meta), path("*.sortedByCoord.out.bam") ], meta.id == "${rna_id}.${allele_key}", from HLAPM_STAR_ALIGN.out.bam_sorted
    ch_gtf        // channel: [ val(meta), path(gtf) ], meta.id == allele_key, from HLAPM_STAR_INDEX.out.gtf

    main:

    // samtools/sort's second/third inputs (a reference fasta+fai and an
    // index format) are only relevant when writing a coordinate-sorted,
    // indexable output; a queryname-sorted BAM is neither, so both are
    // passed as empty.
    SAMTOOLS_SORT(ch_bam_sorted, [ [:], [], [] ], "")

    // One cohort-wide combined GTF (every distinct allele's GTF,
    // concatenated with comment lines stripped), built once per pipeline
    // run - not once per RNA sample.
    HLAPM_COMBINE_GTF(ch_gtf.map { meta, gtf -> gtf }.collect())

    // Group each RNA sample's own queryname-sorted per-allele BAMs back
    // together (STAR_ALIGN/SAMTOOLS_SORT run once per (rna_id, allele_key)
    // pair) so HLAPM_QUANTIFY_READS runs once per RNA sample, over that
    // sample's full set of per-allele BAMs.
    ch_bams_by_sample = SAMTOOLS_SORT.out.bam
        .map { meta, bam -> [ meta.rna_id, bam ] }
        .groupTuple()
        .map { rna_id, bams -> [ [ id: rna_id ], bams ] }

    // HLAPM_COMBINE_GTF runs exactly once for the whole run; `.first()`
    // turns its single-item output into a value channel so it is broadcast
    // to every per-sample HLAPM_QUANTIFY_READS call, rather than being
    // consumed by only the first sample.
    HLAPM_QUANTIFY_READS(ch_bams_by_sample, HLAPM_COMBINE_GTF.out.gtf.first())

    // SAMTOOLS_SORT reports its own version via the topic-based `versions`
    // channel (like STAR_ALIGN/STAR_GENOMEGENERATE elsewhere in this
    // pipeline), collected automatically at the top-level workflow rather
    // than mixed in here.
    ch_versions = HLAPM_COMBINE_GTF.out.versions
        .mix(HLAPM_QUANTIFY_READS.out.versions)

    emit:
    bam_queryname = SAMTOOLS_SORT.out.bam               // channel: [ val(meta), path("*.queryname.bam") ], meta.id == "${rna_id}.${allele_key}"
    edit_distance = HLAPM_QUANTIFY_READS.out.edit_distance // channel: [ val(meta), path("*.edit_distance.tsv") ], meta.id == rna_id
    stat          = HLAPM_QUANTIFY_READS.out.stat          // channel: [ val(meta), path("*.stat.txt") ], meta.id == rna_id
    combined_gtf  = HLAPM_COMBINE_GTF.out.gtf               // channel: [ path("combined.gtf") ]
    versions      = ch_versions
}
