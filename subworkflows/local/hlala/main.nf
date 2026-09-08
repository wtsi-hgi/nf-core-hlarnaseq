include { HLALA_TYPING  } from '../../../modules/nf-core/hlala/typing'
include { HLALA_COMBINE } from '../../../modules/local/hlala/combine'

workflow HLALA {

    take:
    ch_wgs_samplesheet

    main:

    // HLA-LA.pl resolves its graph as `$customGraphDir . '/' . $graph`
    // (opt/hla-la/src/HLA-LA.pl), and HLALA_TYPING invokes it with only
    // `--customGraphDir <graph>` - `--graph` is never passed, so the
    // concatenation appends an empty string and the directory handed to the
    // module must be the prepared graph directory ITSELF, not its parent.
    // The operator-facing contract is deliberately left unchanged
    // (`--hlala_graph_dir` = parent directory, `--hlala_graph` = graph name,
    // an externally-prepared input the pipeline never builds), so the two are
    // joined here into the leaf directory the module actually expects.
    ch_graph = channel.value(file("${params.hlala_graph_dir}/${params.hlala_graph}", checkIfExists: true))

    // The graph is shared by every WGS sample, so broadcast it onto each row
    // to form the module's `tuple val(meta), path(bam), path(bai), path(graph)`.
    ch_typing_input = ch_wgs_samplesheet.combine(ch_graph)

    HLALA_TYPING(ch_typing_input)

    ch_bestguess_g = HLALA_TYPING.out.hla
        .map { meta, hla_files ->
            // `hla` emits the glob `<prefix>/hla/*`, so its payload is the
            // whole HLA-LA result file list; a single-file match can arrive
            // unwrapped rather than as a list, hence the normalisation.
            def files = hla_files instanceof List ? hla_files : [hla_files]
            def bestguess_g = files.find { it.name == 'R1_bestguess_G.txt' }
            if (!bestguess_g) {
                error("HLALA_TYPING produced no R1_bestguess_G.txt for WGS sample '${meta.id}'")
            }
            return [meta, bestguess_g]
        }
        .map { meta, bestguess_g -> [ meta.id, bestguess_g ] }
        .collect(flat: false)
        .map { rows ->
            [
                rows.collect { row -> row[0] },
                rows.collect { row -> row[1] }
            ]
        }

    HLALA_COMBINE(ch_bestguess_g)

    // HLALA_TYPING has no `versions.yml` output - it reports its (container-
    // pinned) version through `topic: versions`, which workflows/hlarnaseq.nf
    // already collects via Channel.topic('versions').
    ch_versions = HLALA_COMBINE.out.versions

    emit:
    combined_csv = HLALA_COMBINE.out.csv
    versions     = ch_versions
}
