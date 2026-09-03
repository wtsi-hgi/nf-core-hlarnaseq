process ARCASHLA_EXTRACT {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // Standard nf-core pattern: one environment.yml feeds the `conda`
    // directive, paired with a matching pinned container. The image below is
    // deliberately the *same* one the vendored nf-core SAMTOOLS_SORT module
    // uses (see modules/nf-core/samtools/sort/main.nf) - the pipeline's only
    // other samtools call site - so the two can never run different samtools
    // versions, and containerized profiles pull no image the pipeline was not
    // already pulling. Like ARCASHLA_VALIDATE_FASTQ (and unlike
    // ARCASHLA_GENOTYPE) this needs no bespoke Dockerfile and no committed
    // .sif: both branches below are public references.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data':
        'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd' }"

    publishDir "${params.outdir}/arcashla/extracted",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    tuple val(meta), path(bam), path(bai), path(unpaired_reads)

    output:
    tuple val(meta), path("${meta.id}.mhc_1.fq.gz"), path("${meta.id}.mhc_2.fq.gz"), emit: reads
    path "versions.yml", emit: versions

    script:
    def unpaired_r1 = unpaired_reads[0]
    def unpaired_r2 = unpaired_reads[1]
    """
    # samtools is provisioned by the conda/container directives above. Fail
    # with an actionable message rather than a bare "command not found" if
    # neither provisioned it - which is what happens when the pipeline is run
    # with no -profile conda/docker/singularity/apptainer at all.
    command -v samtools >/dev/null 2>&1 || {
        echo "ERROR: samtools is not available in the active environment or container. Run with -profile conda, docker, singularity, or apptainer so this module can provision it." >&2
        exit 127
    }

    if [[ "${bai}" != "${bam}.bai" ]]; then
        ln -sf "${bai}" "${bam}.bai"
    fi

    samtools view \
        --uncompressed \
        --fetch-pairs \
        -@ ${task.cpus} \
        -F 2304 \
        "${bam}" \
        "${params.hla_region}" \
        | samtools sort \
            -n \
            -@ ${task.cpus} \
            -T "${meta.id}.sort" \
            -o "${meta.id}.mhc.namesort.bam" \
            -

    samtools fastq \
        -@ ${task.cpus} \
        -0 /dev/null \
        -1 "${meta.id}.bam_1.fq.gz" \
        -2 "${meta.id}.bam_2.fq.gz" \
        -s "${meta.id}.singleton.fq.gz" \
        "${meta.id}.mhc.namesort.bam"

    cat "${unpaired_r1}" "${meta.id}.bam_1.fq.gz" > "${meta.id}.mhc_1.fq.gz"
    cat "${unpaired_r2}" "${meta.id}.bam_2.fq.gz" > "${meta.id}.mhc_2.fq.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version | sed -n '1s/^samtools //p')
    END_VERSIONS
    """

    stub:
    """
    # A minimal but *valid* gzipped FASTQ pair rather than a bare `touch`:
    # tests/default.nf.test asserts these are non-empty, and downstream stubs
    # are handed these paths. Content is not snapshotted (see
    # tests/.nftignore's arcashla/extracted/*.fq.gz entry) - only the names.
    #
    # Before this module had a stub: block, `-profile test -stub-run` fell
    # through to the script: block above and really ran samtools off the host
    # PATH. Stubbing it is what makes the stub pipeline test genuinely
    # engine-free and tool-free.
    printf '@stub_read/1\\nACGT\\n+\\nIIII\\n' | gzip -c > "${meta.id}.mhc_1.fq.gz"
    printf '@stub_read/2\\nACGT\\n+\\nIIII\\n' | gzip -c > "${meta.id}.mhc_2.fq.gz"

    # Hardcoded rather than parsed: environment.yml pins this module to exactly
    # samtools 1.24. Bump both together if that pin ever changes. Left unquoted
    # to match exactly what the script: block's `samtools --version` parse
    # produces (a bare 1.24, which YAML loads as a number) - quoting it would
    # turn the collected version into the string "1.24" and churn
    # tests/default.nf.test.snap for no reason.
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: 1.24
    END_VERSIONS
    """
}
