# HIBAG test fixtures

Fixtures for the SNP-array HLA calling path (`HIBAG_PREDICT`, `HIBAG_COMBINE`,
and `-profile test_hibag`).

## `ModelList.RData` — vendored, GPL-3

**Provenance:** copied verbatim from the installed HIBAG R package, at
`$(Rscript -e 'cat(system.file("extdata", "ModelList.RData", package="HIBAG"))')`
(HIBAG 1.46.0). It is HIBAG's own bundled example model.

**Licence:** HIBAG is distributed under **GPL-3**, and this file is part of that
package. It is vendored here as test data only. The rest of this pipeline is
MIT; this file is not part of the pipeline's distributable code and is not
loaded at runtime by anything other than the tests and `-profile test_hibag`.

**Contents:** a one-element named list `modellist`, holding an `hlaAttrBagObj`
for locus `A` — 100 classifiers, 266 SNPs, 14 HLA alleles, `assembly = "hg19"`,
34 KB.

To regenerate. `bioconductor-hibag` is deliberately not in `envs/nf-core.yml`
any more (`HIBAG_PREDICT` provisions it from
`modules/local/hibag/predict/environment.yml`), so take the package from the
module's own container rather than the launcher environment:

```bash
singularity exec \
  https://depot.galaxyproject.org/singularity/bioconductor-hibag:1.42.0--r44he5774e6_1 \
  Rscript -e 'cat(system.file("extdata","ModelList.RData",package="HIBAG"))'
# then cp that path (from inside the container) to
# tests/fixtures/hibag/ModelList.RData
```

The vendored copy above came from HIBAG 1.46.0, before the module pinned
1.42.0. It has not been re-vendored because the two are byte-identical: the
file shipped inside the 1.42.0 container has the same md5,
`604fa0e2ccaa1424b89013b60857e982`.

### Why the tests set `hibag_match_type = 'RefSNP'`

This model's SNP positions are exactly **1 bp below** the positions in a modern
Illumina manifest — they agree exactly (difference 0) with the
`HapMap_CEU.bim` that HIBAG ships alongside the model, so the example
model/data pair is internally consistent and simply predates the coordinate
convention the fixture genotypes use.

The practical effect, against `NA12878.array.*`:

| `match.type` | model SNPs found |
| --- | --- |
| `Position` | 0 of 266 |
| `Pos+Allele` | 0 of 266 |
| `RefSNP+Position` | 0 of 266 |
| `RefSNP` | **264 of 266** |

So the tests and `conf/test_hibag.config` set `hibag_match_type = 'RefSNP'`.
The pipeline default stays the stricter `RefSNP+Position`, which is correct for
a model built against the same manifest and assembly as the operator's data.
`modules/local/hibag/predict/tests/nextflow_no_overlap.config` deliberately
keeps the strict default in order to exercise the no-overlap error path.

## `NA12878.array.{bed,bim,fam}` — ours

NA12878's Illumina HumanOmniExpress-24 v1.0 genotypes, produced by
`testdata-make/10-prepare-na12878-array-hibag` and then subset to the 266 SNPs
of the model above (264 of them are present). GRCh37/hg19, one sample, ~7 KB.

This makes the module test a real imputation with a known right answer:
**NA12878 is A\*01:01 / A\*11:01**, which HIBAG recovers at posterior
probability 0.989.

To regenerate, run `testdata-make/10-prepare-na12878-array-hibag` and subset
`hlarnases-testdata/array/NA12878.omniexpress.xMHC.hg19.*` to the rsIDs in
`modellist[["A"]]$snp.id`.

## `array_samples.csv`

Samplesheet used by `-profile test_hibag`, pointing at the PLINK fixture above.

## `combine/*.hibag_calls.tsv`

Hand-written per-dataset call files for the `HIBAG_COMBINE` tests: two
populated datasets (deliberately given to the process in non-sorted order) and
one header-only file.
