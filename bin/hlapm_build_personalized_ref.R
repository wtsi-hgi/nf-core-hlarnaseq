#!/usr/bin/env Rscript

### Description
# Build personalized bulk-RNA HLA references from per-individual HLA
# allele-list TSVs, using HLApm (https://github.com/davenportlab/HLApm).
#
# Ported from artifacts/scripts/hlapm-personref.R. Locus filtering (the
# original script's blacklist_loci / exclude_hla_loci() step) is dropped
# here: the upstream Python converter (bin/consensus_to_hlapm.py) already
# enforces an explicit allow-list (--hlapm_allowed_loci) before this script
# ever sees the data, so a second, redundant filtering step would only
# invite ambiguity.
#
# Usage: hlapm_build_personalized_ref.R <bulk|sc> <output_dir> <sample_tsv> [<sample_tsv> ...]
# Requires the HLAPM_HOME environment variable to point at a local,
# pre-cloned checkout of https://github.com/davenportlab/HLApm.

#' Add "HLA-" prefix to all HLA alleles
#'
#' @param df A data.frame with unprefixed HLA alleles (e.g. "A*01:01") in the
#'   second column.
#' @return A data.frame with "HLA-" prefixed to each allele in the second
#'   column (e.g. "HLA-A*01:01").
add_hla_prefix <- function(df) {
  df[[2]] <- paste0("HLA-", df[[2]])
  return(df)
}

### Reading shell variable with HLApm checkout location
HLAPM_HOME <- Sys.getenv("HLAPM_HOME")
if (identical(HLAPM_HOME, "")) {
  stop("HLAPM_HOME environment variable is not set; it must point to a local HLApm checkout.")
}
message("HLApm repo location: ", HLAPM_HOME)

# This global variable is required by HLApm scripts to fuction correctly
DIR_personalizedHLA <- HLAPM_HOME

### Command-line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: hlapm_build_personalized_ref.R <bulk|sc> <output_dir> <sample_tsv> [<sample_tsv> ...]")
}

run_mode <- args[1] # Whether to run in bulk RNA-seq or single-cell mode
message("Run mode: ", run_mode)
output_dir <- args[2]
samples <- args[3:length(args)]

if (!(run_mode %in% c("bulk", "sc"))) {
  stop("Unknown run mode '", run_mode, "': expected 'bulk' or 'sc'.")
}

if (run_mode == "sc") {
  stop(
    "Single-cell ('sc') mode is out of scope for this pipeline iteration ",
    "(bulk RNA-seq only); only 'bulk' mode (bulkRNA_build_personalized_HLA_ref()) is supported."
  )
}

### Loading HLApm libraries
source(file.path(HLAPM_HOME, "scripts", "load_ref.R"))
source(file.path(HLAPM_HOME, "scripts", "make_personalized_HLA_ref.R"))
source(file.path(HLAPM_HOME, "scripts", "align_and_adjust_annotation.R"))
source(file.path(HLAPM_HOME, "scripts", "bulk", "functions_personalized_HLA_ref.R"))
source(file.path(HLAPM_HOME, "scripts", "bulk", "functions_star.R"))

### Patch: HLApm's get_DRB_haplotypes() (scripts/make_personalized_HLA_ref.R)
# crashes with "Error in order(...) : argument 1 is not a vector" for any
# individual with zero HLA-DRB1 alleles genotyped (a real, expected outcome
# for RNA-seq-only calling - arcasHLA frequently fails to confidently call
# DRB1). Root cause: strsplit(character(0), ";") returns list(), and
# unlist(list()) returns NULL rather than character(0); order(NULL) then
# errors. This redefinition is byte-for-byte identical to the upstream
# function except for the added is.null() guard below, which restores the
# function's own intended "no DRB paralogous genes" fallback for this case
# instead of crashing before reaching it. See artifacts/ for the full bug
# writeup. Remove this patch if/when upstream HLApm fixes the issue.
get_DRB_haplotypes <- function(input_alleles, individual_ID=""){

  if(individual_ID==""){
      print("no sample name found")
  }

  drb1 <- input_alleles[grep("DRB1", input_alleles$HLA_allele),]
  drb1 <- drb1[drb1$individual_ID==individual_ID, c("HLA_allele")]
  drb1 <- unique( gsub("HLA-DRB1\\*(\\d{2})\\:\\d+.*", "\\1", drb1) )

  other_drbs <- drb_haplotypes[drb_haplotypes$DRB1 %in% drb1,]$DRB_par
  other_drbs <- unique( unlist( strsplit( other_drbs, ";") ) )
  if (is.null(other_drbs)) other_drbs <- character(0)  # patched: was NULL when drb1 has no match, crashing order() below
  other_drbs <- other_drbs[order(other_drbs)]
  protein_coding_drbs <- unique( other_drbs[(other_drbs %in% c("DRB3", "DRB4", "DRB5"))] )
  print( paste0( "DRB paralogous genes: ", paste0(protein_coding_drbs, collapse = ", ") ) )


  if(length(protein_coding_drbs) >0){
      per.drb_fa <- DRB_fa[names(DRB_fa) %in% c( paste0("chr_HLA-", protein_coding_drbs) ) ]
      per.drb_gtf <- DRB_gtf[DRB_gtf$gene_name %in% c( paste0("HLA-", protein_coding_drbs) ), ]

      out_drb <- list(per.drb_fa, per.drb_gtf)
  }
  if(length(protein_coding_drbs) ==0){
    print("no DRB paralogous genes")
    out_drb="no_DRB_paralogous_genes"
  }
  return(out_drb)
}

### Loading and processing sample data
for (sample in samples) {
  message("### Processing sample file: ", sample)

  # Clean up input alleles
  input_alleles <- read.table(sample, header = TRUE)
  input_alleles <- add_hla_prefix(input_alleles)

  # Get personalized HLA reference and annotation for bulk RNA-seq
  bulkRNA_build_personalized_HLA_ref(input_alleles, output_directory = output_dir)
}
