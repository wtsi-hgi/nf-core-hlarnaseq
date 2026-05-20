#!/usr/bin/env bash
set -euo pipefail

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="artifacts/validation/${RUN_ID}"
mkdir -p "${RUN_DIR}"

FAILURES=()

run_check() {
    local label="$1"
    local log_name="$2"
    shift 2
    local log_file="${RUN_DIR}/${log_name}.log"

    echo "== ${label} =="
    {
        echo "Command: $*"
        echo
    } | tee "${log_file}"

    set +e
    "$@" 2>&1 | tee -a "${log_file}"
    local status=${PIPESTATUS[0]}
    set -e

    if [[ "${status}" -eq 0 ]]; then
        echo "PASS: ${label}" | tee -a "${log_file}"
    else
        echo "FAIL: ${label} exited with status ${status}" | tee -a "${log_file}"
        FAILURES+=("${label} (${status})")
    fi
}

skip_check() {
    local label="$1"
    local reason="$2"
    local log_name="$3"
    local log_file="${RUN_DIR}/${log_name}.log"

    echo "== ${label} =="
    echo "SKIP: ${reason}" | tee "${log_file}"
}

echo "== Environment =="
{
    echo "Validation run: ${RUN_ID}"
    echo "Run directory: ${RUN_DIR}"
    command -v nextflow || true
    command -v nf-core || true
    command -v nf-test || true
    command -v pre-commit || true
    echo "Container validation: skipped by early-stage Conda policy"
} | tee "${RUN_DIR}/environment.log"

if command -v nf-core >/dev/null 2>&1; then
    run_check "nf-core lint" "nf-core-lint" nf-core pipelines lint
else
    skip_check "nf-core lint" "nf-core is not installed" "nf-core-lint"
fi

if command -v nf-test >/dev/null 2>&1; then
    run_check "nf-test" "nf-test" nf-test test
else
    skip_check "nf-test" "nf-test is not installed" "nf-test"
fi

if command -v nextflow >/dev/null 2>&1; then
    run_check "Nextflow test profile" "nextflow-test" \
        nextflow run . -profile test --outdir "${RUN_DIR}/nextflow-test"

    run_check "Nextflow debug,test profile" "nextflow-debug-test" \
        nextflow run . -profile debug,test --outdir "${RUN_DIR}/nextflow-debug-test"

    skip_check "Nextflow test,docker profile" "containerized validation is intentionally out of scope for the current early-stage Conda policy" "nextflow-test-docker"
    skip_check "Nextflow debug,test,docker profile" "containerized validation is intentionally out of scope for the current early-stage Conda policy" "nextflow-debug-test-docker"
else
    skip_check "Nextflow test profile" "nextflow is not installed" "nextflow-test"
    skip_check "Nextflow debug,test profile" "nextflow is not installed" "nextflow-debug-test"
    skip_check "Nextflow test,docker profile" "containerized validation is intentionally out of scope for the current early-stage Conda policy" "nextflow-test-docker"
    skip_check "Nextflow debug,test,docker profile" "containerized validation is intentionally out of scope for the current early-stage Conda policy" "nextflow-debug-test-docker"
fi

if command -v pre-commit >/dev/null 2>&1; then
    run_check "pre-commit" "pre-commit" pre-commit run --all-files
else
    skip_check "pre-commit" "pre-commit is not installed" "pre-commit"
fi

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
    echo "Validation completed with failures:"
    printf ' - %s\n' "${FAILURES[@]}"
    echo "Logs: ${RUN_DIR}"
    exit 1
fi

echo "Validation completed without command failures."
echo "Logs: ${RUN_DIR}"
