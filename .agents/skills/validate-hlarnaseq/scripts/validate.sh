#!/usr/bin/env bash
set -euo pipefail

echo "== Environment =="
command -v nextflow || true
command -v nf-core || true
command -v nf-test || true
command -v pre-commit || true

echo "== nf-core lint =="
if command -v nf-core >/dev/null 2>&1; then
    nf-core pipelines lint
else
    echo "SKIP: nf-core is not installed"
fi

echo "== nf-test =="
if command -v nf-test >/dev/null 2>&1; then
    nf-test test
else
    echo "SKIP: nf-test is not installed"
fi

echo "== Nextflow test profile =="
if command -v nextflow >/dev/null 2>&1; then
    nextflow run . -profile test --outdir artifacts/validation/nextflow-test
else
    echo "SKIP: nextflow is not installed"
fi

echo "== pre-commit =="
if command -v pre-commit >/dev/null 2>&1; then
    pre-commit run --all-files
else
    echo "SKIP: pre-commit is not installed"
fi

