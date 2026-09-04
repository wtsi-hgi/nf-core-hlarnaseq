process HLAPM_BUILD_REF {
    tag "hlapm_build_ref"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // nextflow.config sets docker.registry/singularity.registry = 'quay.io'
    // for every container engine, so a bare "hlarnaseq/..." tag would
    // resolve as quay.io/hlarnaseq/... and fail to pull (nothing is pushed
    // there). Docker matches a local image already tagged with that full
    // reference with no network access; Singularity/Apptainer have no access
    // to Docker's local image store at all, so they instead reference a local
    // .sif file built from that same image (see scripts/build_image_hlapm.sh)
    // directly by path - Nextflow uses a local file as-is, no pull, no
    // registry involved.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        "${moduleDir}/hlapm-build-ref.sif" :
        'quay.io/hlarnaseq/hlapm-build-ref:38faa60' }"

    publishDir "${params.outdir}/hlapm/personalized_ref",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    path sample_tsvs
    // Optional --hlapm_repo override, staged (not interpolated) on purpose:
    // a bare host path interpolated into the script is invisible inside a
    // container, whereas a staged path input is mounted by Nextflow. Empty
    // list when unset, in which case the container's baked-in /opt/HLApm is
    // used instead. Same pattern as HLALA_TYPING's graph directory.
    path hlapm_repo, stageAs: 'hlapm_repo'

    output:
    path "out", emit: personalized_ref
    path "versions.yml", emit: versions

    script:
    def sample_tsv_args = (sample_tsvs instanceof List ? sample_tsvs : [sample_tsvs]).join(' ')
    def hlapm_home = hlapm_repo ? '"\$(readlink -f hlapm_repo)"' : '"/opt/HLApm"'
    """
    # The conda/container directives above provision the R stack. Neither
    # applies when the pipeline is run with no -profile conda/docker/
    # singularity/apptainer at all, in which case the task falls back to the
    # host PATH - fail with an actionable message rather than a bare
    # "command not found", as HIBAG_PREDICT does.
    command -v Rscript >/dev/null 2>&1 || {
        echo "ERROR: Rscript is not available. Run the pipeline with -profile conda, docker, singularity, or apptainer so this module gets the environment declared in modules/local/hlapm/build_ref/environment.yml." >&2
        exit 127
    }

    # HLApm itself is an unpackaged git repository, so unlike the R stack it
    # cannot come from environment.yml: the container bakes it in at
    # /opt/HLApm, and every other profile needs --hlapm_repo (staged above as
    # ./hlapm_repo when set).
    export HLAPM_HOME=${hlapm_home}

    if [[ ! -d "\${HLAPM_HOME}" ]]; then
        echo "ERROR: no HLApm checkout found at \${HLAPM_HOME}. Either run the pipeline with -profile docker, singularity, or apptainer (the image bakes HLApm in - build it once with scripts/build_image_hlapm.sh), or pass --hlapm_repo pointing at a local clone of https://github.com/davenportlab/HLApm." >&2
        exit 127
    fi

    mkdir -p out

    hlapm_build_personalized_ref.R bulk out ${sample_tsv_args}

    # The baked-in checkout records its pinned commit in a plain file (the
    # image drops .git); a --hlapm_repo override is a real checkout, so fall
    # back to asking git what it is.
    if [[ -s "\${HLAPM_HOME}/HLApm.version" ]]; then
        hlapm_version=\$(cat "\${HLAPM_HOME}/HLApm.version")
    else
        set +e
        hlapm_version=\$(git -C "\${HLAPM_HOME}" rev-parse HEAD 2>&1)
        set -e
    fi
    if [[ -z "\${hlapm_version}" ]] || [[ "\${hlapm_version}" == *"fatal"* ]]; then
        hlapm_version="unknown"
    fi

    set +e
    r_version=\$(Rscript -e 'cat(as.character(getRversion()))' 2>&1)
    set -e
    if [[ -z "\${r_version}" ]]; then
        r_version="unknown"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "\${r_version}"
        HLApm: "\${hlapm_version}"
    END_VERSIONS
    """

    stub:
    def sample_tsv_args = (sample_tsvs instanceof List ? sample_tsvs : [sample_tsvs]).join(' ')
    """
    mkdir -p out

    for sample_tsv in ${sample_tsv_args}; do
        individual_id=\$(basename "\${sample_tsv}" .tsv)
        mkdir -p "out/\${individual_id}"
        printf '>placeholder_allele\\nACGT\\n' > "out/\${individual_id}/placeholder_allele.fa"
        printf 'placeholder_allele\\tHLApm_stub\\texon\\t1\\t4\\t.\\t+\\t.\\tgene_id "placeholder_allele";\\n' > "out/\${individual_id}/placeholder_allele.gtf"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "unknown"
        HLApm: "unknown"
    END_VERSIONS
    """
}
