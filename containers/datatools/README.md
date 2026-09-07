# `datatools` shared container

The python3 + R environment behind this pipeline's own `bin/` analysis scripts.
Build it with [`scripts/build_image_datatools.sh`](../../scripts/build_image_datatools.sh).

## Why this one is not module-local

Every other environment in this repository lives next to the single module that
uses it, and each module's `conda` directive points at `${moduleDir}/environment.yml`.
This one is shared by four modules:

| Module                       | Script                             | Uses                                    |
| ---------------------------- | ---------------------------------- | --------------------------------------- |
| `HLA_CONSENSUS`              | `bin/call_hla_consensus.py`        | python3, pandas                         |
| `HLAPM_PREPARE_INPUT`        | `bin/consensus_to_hlapm.py`        | python3 (stdlib only)                   |
| `ARCASHLA_COMBINE`           | `bin/combine_arcashla_genotypes.R` | jsonlite, dplyr, tibble, stringr, purrr |
| `HLAPM_SUMMARIZE_READCOUNTS` | `bin/summarize_hla_readcounts.R`   | dplyr, tidyr                            |

These are small data transformations over the same two interpreters, with
overlapping package lists. Four module-local copies would give slightly smaller
`-profile conda` environments, at the cost of four specs that must be kept in
step with each other and with one image - exactly the drift this repository
avoids elsewhere by deriving `conda` and `container` from a single file. So the
four modules point their `conda` directive at
`${projectDir}/containers/datatools/environment.yml` and their `container`
directive at the image built from it.

This is a deliberate deviation from the nf-core module layout, not an oversight.
A module that needs a tool of its own - rather than these shared interpreters -
should still get its own module-local `environment.yml`, as
`HLAPM_BUILD_REF`, `ARCASHLA_GENOTYPE`, `HLAPM_QUANTIFY_READS` and
`HIBAG_PREDICT` all do.

## Adding a package

Add it to `environment.yml`, pinned, then rebuild and bump the image tag
(`IMAGE_TAG` in `scripts/build_image_datatools.sh`, and the `container`
directive in each of the four modules - they must agree). Bump the tag whenever
the environment changes, so an image and a tag always mean the same contents;
operators build this image locally, and a moved tag with an unchanged name is
indistinguishable from a stale build.

Prefer adding a package here only if it serves a `bin/` script of this kind. A
module wrapping a real bioinformatics tool belongs in its own module-local
environment, where its pins can move independently of everything else.

## Versions

Pinned to the versions this pipeline's existing published results were produced
with, so containerization changes no output. `r-tidyr` is the one exception - it
had no build for the pinned `r-base`, so it necessarily moved; see the note in
`environment.yml`.
