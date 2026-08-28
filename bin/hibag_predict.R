#!/usr/bin/env Rscript

# Predict HLA alleles from SNP-array genotypes with HIBAG, and write the calls
# in the same format that HLALA_COMBINE produces, so the result can be fed to
# call_hla_consensus.py in place of HLA-LA output.
#
#   sample_id <TAB> Locus <TAB> HLA_allele
#   NA12878         A         A*01:01
#   NA12878         A         A*11:01
#
# One allele per row, two rows per (sample, locus). Sample IDs come from the
# IID column of the PLINK .fam file -- a PLINK fileset holds many samples, and
# HIBAG predicts all of them at once, so it is those IIDs that must line up
# with the WGS sample IDs in the pipeline's sample key.

suppressPackageStartupMessages(library(HIBAG))

MATCH_TYPES <- c("Position", "Pos+Allele", "RefSNP+Position", "RefSNP")

# -------------------------------------------------------------------------
# Arguments
# -------------------------------------------------------------------------

parse_args <- function(argv) {
    defaults <- list(
        bed = NULL, bim = NULL, fam = NULL, model = NULL, `out-prefix` = NULL,
        `match-type` = "RefSNP+Position", assembly = "hg19",
        `min-prob` = "0", loci = NULL
    )
    if (length(argv) %% 2L != 0L) {
        stop("each option must be followed by a value; got an odd number of arguments", call. = FALSE)
    }
    args <- defaults
    if (length(argv) > 0L) {
        keys <- argv[c(TRUE, FALSE)]
        values <- argv[c(FALSE, TRUE)]
        for (i in seq_along(keys)) {
            key <- sub("^--", "", keys[i])
            if (!key %in% names(defaults)) {
                stop(sprintf("unknown option '%s'; expected one of: %s",
                             keys[i], paste0("--", names(defaults), collapse = ", ")),
                     call. = FALSE)
            }
            args[[key]] <- values[i]
        }
    }
    for (required in c("bed", "bim", "fam", "model", "out-prefix")) {
        if (is.null(args[[required]])) {
            stop(sprintf("--%s is required", required), call. = FALSE)
        }
    }
    if (!args[["match-type"]] %in% MATCH_TYPES) {
        stop(sprintf("--match-type must be one of: %s", paste(MATCH_TYPES, collapse = ", ")),
             call. = FALSE)
    }
    args[["min-prob"]] <- suppressWarnings(as.numeric(args[["min-prob"]]))
    if (is.na(args[["min-prob"]]) || args[["min-prob"]] < 0 || args[["min-prob"]] > 1) {
        stop("--min-prob must be a number between 0 and 1", call. = FALSE)
    }
    args
}

# -------------------------------------------------------------------------
# Model loading
# -------------------------------------------------------------------------

# Published HIBAG models are distributed either as a named list of
# hlaAttrBagObj (one per locus) or as a single hlaAttrBagObj. Accept both.
load_model_objects <- function(path) {
    env <- new.env(parent = emptyenv())
    loaded <- load(path, envir = env)
    if (length(loaded) < 1L) {
        stop(sprintf("model file contains no objects: %s", path), call. = FALSE)
    }
    obj <- get(loaded[1L], envir = env)

    if (inherits(obj, "hlaAttrBagObj")) {
        models <- list(obj)
        names(models) <- obj$hla.locus
        return(models)
    }
    if (is.list(obj) && length(obj) > 0L && all(vapply(obj, inherits, logical(1L), "hlaAttrBagObj"))) {
        if (is.null(names(obj)) || any(!nzchar(names(obj)))) {
            names(obj) <- vapply(obj, function(m) m$hla.locus, character(1L))
        }
        return(obj)
    }
    stop(sprintf(paste("model file '%s' holds a '%s', not a HIBAG model.",
                       "Expected an hlaAttrBagObj or a named list of hlaAttrBagObj."),
                 path, paste(class(obj), collapse = "/")), call. = FALSE)
}

# -------------------------------------------------------------------------
# SNP matching diagnostics
# -------------------------------------------------------------------------

COMPLEMENT <- c(A = "T", T = "A", C = "G", G = "C")

# Normalise an "A/B" allele pair so that strand and A/B order do not matter,
# which is how a Pos+Allele match can succeed despite differing orientation.
allele_key <- function(alleles) {
    parts <- strsplit(as.character(alleles), "/", fixed = TRUE)
    vapply(parts, function(p) {
        if (length(p) != 2L) return(NA_character_)
        forward <- paste(sort(p), collapse = "/")
        flipped <- paste(sort(unname(COMPLEMENT[p])), collapse = "/")
        if (is.na(flipped)) forward else min(forward, flipped)
    }, character(1L))
}

# How many of the model's SNPs can be found in the genotypes under each
# criterion. Used to explain a no-overlap failure rather than let HIBAG abort
# with a bare "There is no overlapping of SNPs!".
overlap_counts <- function(model, geno) {
    c(
        "Position" = length(intersect(model$snp.position, geno$snp.position)),
        "Pos+Allele" = length(intersect(
            paste(model$snp.position, allele_key(model$snp.allele)),
            paste(geno$snp.position, allele_key(geno$snp.allele))
        )),
        "RefSNP+Position" = length(intersect(
            paste(model$snp.id, model$snp.position),
            paste(geno$snp.id, geno$snp.position)
        )),
        "RefSNP" = length(intersect(model$snp.id, geno$snp.id))
    )
}

format_overlap <- function(counts, n_model_snps) {
    paste(sprintf("      %-16s %d of %d model SNPs", names(counts), counts, n_model_snps),
          collapse = "\n")
}

no_overlap_error <- function(locus, match_type, counts, n_model_snps) {
    workable <- names(counts)[counts > 0L]
    hint <- if (length(workable) > 0L) {
        sprintf("Try --match-type with one of: %s.", paste(workable, collapse = ", "))
    } else {
        paste("No criterion matches any SNP. Check that the model and the array",
              "data use the same genome assembly, and that the array covers the",
              "xMHC region.")
    }
    stop(sprintf(paste0(
        "HLA-%s: none of the model's %d SNPs match the array data under ",
        "--match-type '%s'.\n    SNPs found under each criterion:\n%s\n    %s"),
        locus, n_model_snps, match_type, format_overlap(counts, n_model_snps), hint),
        call. = FALSE)
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

main <- function() {
    args <- parse_args(commandArgs(trailingOnly = TRUE))
    match_type <- args[["match-type"]]
    min_prob <- args[["min-prob"]]

    geno <- hlaBED2Geno(
        bed.fn = args$bed, fam.fn = args$fam, bim.fn = args$bim,
        assembly = args$assembly, import.chr = "xMHC", verbose = TRUE
    )
    cat(sprintf("Imported %d SNPs for %d sample(s)\n",
                length(geno$snp.id), length(geno$sample.id)))

    models <- load_model_objects(args$model)
    if (!is.null(args$loci)) {
        wanted <- trimws(strsplit(args$loci, ",", fixed = TRUE)[[1L]])
        wanted <- wanted[nzchar(wanted)]
        missing <- setdiff(wanted, names(models))
        if (length(missing) > 0L) {
            stop(sprintf("--loci requested %s, but the model file only provides %s",
                         paste(missing, collapse = ", "), paste(names(models), collapse = ", ")),
                 call. = FALSE)
        }
        models <- models[wanted]
    }
    cat(sprintf("Predicting %d locus/loci: %s\n", length(models), paste(names(models), collapse = ", ")))

    calls <- list()
    posterior <- list()

    for (locus in names(models)) {
        model <- hlaModelFromObj(models[[locus]])
        counts <- overlap_counts(models[[locus]], geno)
        n_model_snps <- length(models[[locus]]$snp.id)
        n_matched <- unname(counts[match_type])
        if (n_matched < 1L) {
            no_overlap_error(locus, match_type, counts, n_model_snps)
        }
        cat(sprintf("HLA-%s: %d of %d model SNPs matched under '%s'\n",
                    locus, n_matched, n_model_snps, match_type))

        pred <- hlaPredict(model, geno, type = "response+prob",
                           match.type = match_type, verbose = FALSE)
        value <- pred$value
        value$locus <- locus
        value$n_model_snps <- n_model_snps
        value$n_matched_snps <- n_matched
        posterior[[locus]] <- value

        for (i in seq_len(nrow(value))) {
            row <- value[i, ]
            prob <- if (is.null(row$prob) || is.na(row$prob)) NA_real_ else row$prob
            if (!is.na(prob) && prob < min_prob) {
                cat(sprintf("  dropped %s HLA-%s: posterior %.4f below --min-prob %.4f\n",
                            row$sample.id, locus, prob, min_prob))
                next
            }
            for (allele in c(row$allele1, row$allele2)) {
                if (is.na(allele) || !nzchar(allele)) {
                    cat(sprintf("  dropped %s HLA-%s: no allele call\n", row$sample.id, locus))
                    next
                }
                calls[[length(calls) + 1L]] <- data.frame(
                    sample_id = as.character(row$sample.id),
                    Locus = locus,
                    HLA_allele = paste0(locus, "*", allele),
                    stringsAsFactors = FALSE
                )
            }
        }
    }

    calls_df <- if (length(calls) > 0L) {
        do.call(rbind, calls)
    } else {
        data.frame(sample_id = character(0L), Locus = character(0L),
                   HLA_allele = character(0L), stringsAsFactors = FALSE)
    }
    # Sorted so the output is deterministic regardless of locus iteration order.
    calls_df <- calls_df[order(calls_df$sample_id, calls_df$Locus, calls_df$HLA_allele), , drop = FALSE]

    calls_file <- paste0(args[["out-prefix"]], ".hibag_calls.tsv")
    write.table(calls_df, calls_file, sep = "\t", quote = FALSE,
                row.names = FALSE, col.names = TRUE)

    posterior_df <- do.call(rbind, posterior)
    posterior_file <- paste0(args[["out-prefix"]], ".hibag_posterior.tsv")
    if (is.null(posterior_df)) {
        posterior_df <- data.frame(sample_id = character(0L), locus = character(0L),
                                   allele1 = character(0L), allele2 = character(0L),
                                   prob = numeric(0L), matching = numeric(0L),
                                   n_model_snps = integer(0L), n_matched_snps = integer(0L),
                                   stringsAsFactors = FALSE)
    } else {
        names(posterior_df)[names(posterior_df) == "sample.id"] <- "sample_id"
        keep <- intersect(c("sample_id", "locus", "allele1", "allele2", "prob",
                            "matching", "n_model_snps", "n_matched_snps"),
                          names(posterior_df))
        posterior_df <- posterior_df[order(posterior_df$sample_id, posterior_df$locus), keep, drop = FALSE]
    }
    write.table(posterior_df, posterior_file, sep = "\t", quote = FALSE,
                row.names = FALSE, col.names = TRUE)

    cat(sprintf("Wrote %d allele rows to %s\n", nrow(calls_df), calls_file))
}

main()
