process HLAPM_BUILD_REF {
    tag "hlapm_build_ref"
    label 'process_medium'

    publishDir "${params.outdir}/hlapm/personalized_ref",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename == 'versions.yml' ? null : filename }

    input:
    path sample_tsvs

    output:
    path "out", emit: personalized_ref
    path "versions.yml", emit: versions

    script:
    def sample_tsv_args = (sample_tsvs instanceof List ? sample_tsvs : [sample_tsvs]).join(' ')
    """
    HLAPM_CONDA_ENV="hlapm"

    command -v conda >/dev/null 2>&1 || {
        echo "ERROR: conda is required to run HLApm from the \${HLAPM_CONDA_ENV} environment" >&2
        exit 127
    }

    conda run -n "\${HLAPM_CONDA_ENV}" bash -lc 'command -v Rscript >/dev/null 2>&1' || {
        echo "ERROR: Rscript is not available in the \${HLAPM_CONDA_ENV} Conda environment" >&2
        exit 127
    }

    mkdir -p out

    export HLAPM_HOME="${params.hlapm_repo}"

    conda run -n "\${HLAPM_CONDA_ENV}" Rscript "${projectDir}/bin/hlapm_build_personalized_ref.R" bulk out ${sample_tsv_args}

    set +e
    hlapm_version=\$(git -C "${params.hlapm_repo}" rev-parse HEAD 2>&1)
    set -e
    if [[ -z "\${hlapm_version}" ]] || [[ "\${hlapm_version}" == *"fatal"* ]]; then
        hlapm_version="unknown"
    fi

    set +e
    r_version=\$(conda run -n "\${HLAPM_CONDA_ENV}" Rscript -e 'cat(as.character(getRversion()))' 2>&1)
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
}
