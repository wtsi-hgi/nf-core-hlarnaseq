process HLAPM_QUANTIFY_READS {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // nextflow.config sets docker.registry/singularity.registry = 'quay.io'
    // for every container engine, so a bare "hlarnaseq/..." tag would resolve
    // as quay.io/hlarnaseq/... and fail to pull (nothing is pushed there).
    // Docker matches a local image already tagged with that full reference
    // with no network access; Singularity/Apptainer have no access to
    // Docker's local image store at all, so they instead reference a local
    // .sif file built from that same image (see
    // scripts/build_image_hlapm_quantify.sh) directly by path.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${moduleDir}/hlapm-quantify-reads.sif" :
        'quay.io/hlarnaseq/hlapm-quantify-reads:py2.7.15' }"

    input:
    tuple val(meta), path(bams)
    path combined_gtf

    output:
    tuple val(meta), path("${meta.id}.edit_distance.tsv"), emit: edit_distance
    tuple val(meta), path("${meta.id}.stat.txt"),          emit: stat
    path "versions.yml",                                  emit: versions

    script:
    // Sort alphabetically by filename so the output TSV's per-BAM columns
    // are deterministic (not whatever order groupTuple() happened to
    // deliver) and group all alleles of one locus in adjacent columns,
    // loci themselves in sorted order - filenames are
    // "<sample>.<LOCUS>_<allele>__<hash>.queryname.bam", so a plain
    // alphabetical sort already achieves both.
    def bam_list = (bams instanceof List ? bams : [bams]).sort { it.getName() }
    def bam_args = bam_list.collect { "\"${it}\"" }.join(' ')
    """
    # The conda/container directives above provision Python 2 and its two
    # packages. Neither applies when the pipeline is run with no -profile
    # conda/docker/singularity/apptainer at all, in which case the task falls
    # back to the host PATH - fail with an actionable message rather than a
    # bare "command not found", as HIBAG_PREDICT does.
    command -v python2 >/dev/null 2>&1 || {
        echo "ERROR: python2 is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in modules/local/hlapm/quantify_reads/environment.yml." >&2
        exit 127
    }

    # Staged onto PATH from bin/ by Nextflow, and carries its own
    # "#!/usr/bin/env python2" shebang. Invoked by name rather than as
    # "\${projectDir}/bin/..." because that path does not exist inside a
    # container.
    make_a_table_210804_allHLAgenes.py -g "" -t "" "${combined_gtf}" ${bam_args} > "${meta.id}.edit_distance.tsv" 2> "${meta.id}.stat.txt"

    # make_a_table_210804_allHLAgenes.py has no --version flag of its own;
    # report the interpreter and the two libraries that actually determine its
    # behaviour instead (best-effort, matching ARCASHLA_GENOTYPE's precedent
    # for tools without a clean --version flag). pybam reports "1.0" for every
    # commit, so the image additionally records the exact commit it installed
    # in \$PYBAM_COMMIT - preferred here when present.
    set +e
    python_version=\$(python2 --version 2>&1 | sed 's/^Python //')
    # Both are queried through pkg_resources rather than a module __version__
    # attribute: intervaltree 3.1.0 does not define one, and pybam defines
    # neither.
    intervaltree_version=\$(python2 -c "import pkg_resources; print(pkg_resources.get_distribution('intervaltree').version)" 2>/dev/null)
    pybam_version="\${PYBAM_COMMIT:-}"
    if [[ -z "\${pybam_version}" ]]; then
        pybam_version=\$(python2 -c "import pkg_resources; print(pkg_resources.get_distribution('pybam').version)" 2>/dev/null)
    fi
    set -e
    if [[ -z "\${python_version}" ]]; then
        python_version="unknown"
    fi
    if [[ -z "\${intervaltree_version}" ]]; then
        intervaltree_version="unknown"
    fi
    if [[ -z "\${pybam_version}" ]]; then
        pybam_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python2: "\${python_version}"
        intervaltree: "\${intervaltree_version}"
        pybam: "\${pybam_version}"
    END_VERSIONS
    """

    stub:
    def bam_list = (bams instanceof List ? bams : [bams]).sort { it.getName() }
    def header_cols = (['read_name', 'gene_name_confidence', 'gene_name'] + bam_list.collect { it.getName() }).join('\t')
    def stub_row = (['stub_read_1', 'unique', 'placeholder_allele'] + bam_list.collect { 'NA' }).join('\t')
    """
    printf '${header_cols}\\n' > "${meta.id}.edit_distance.tsv"
    printf '${stub_row}\\n' >> "${meta.id}.edit_distance.tsv"

    echo "stub run: no real statistics computed" > "${meta.id}.stat.txt"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python2: "unknown"
        intervaltree: "unknown"
        pybam: "unknown"
    END_VERSIONS
    """
}
