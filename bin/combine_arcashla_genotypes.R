#!/usr/bin/env Rscript

# Combine per-sample arcasHLA genotype JSON files into one long-format CSV
# (one row per HLA gene per sample), padding genes missing from a sample's
# JSON with NA alleles.
#
# Usage:
#   combine_arcashla_genotypes.R <manifest.tsv> <output.csv>
#
# <manifest.tsv> is a headerless, tab-separated file with one row per
# sample: sample_id<TAB>genotype_json_path

library(jsonlite)
library(dplyr)
library(tibble)
library(stringr)
library(purrr)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 2) {
  stop(
    "Usage: combine_arcashla_genotypes.R <manifest.tsv> <output.csv>",
    call. = FALSE
  )
}

manifest_path <- args[1]
output_path <- args[2]

manifest <- read.delim(
  manifest_path,
  header = FALSE,
  sep = "\t",
  col.names = c("sample_id", "genotype_json_path"),
  stringsAsFactors = FALSE
)

if (nrow(manifest) == 0) {
  stop("No genotype JSON files listed in manifest: ", manifest_path, call. = FALSE)
}

sample_names <- manifest$sample_id
files <- manifest$genotype_json_path

all_HLA_genes <- tibble(HLA_gene = c(
  "HLA-A", "HLA-B", "HLA-C", "HLA-DMA", "HLA-DMB", "HLA-DOA", "HLA-DOB",
  "HLA-DPA1", "HLA-DPB1", "HLA-DQA1", "HLA-DQB1", "HLA-DRA", "HLA-DRB1",
  "HLA-DRB3", "HLA-DRB5", "HLA-E", "HLA-F", "HLA-H", "HLA-J", "HLA-K", "HLA-L"
))

# Helper: parse one file safely and return a tibble with expected columns
parse_one_arcas <- function(path, sample_name, all_HLA_genes) {
  tryCatch({
    raw <- fromJSON(path, simplifyVector = TRUE)

    df <- raw %>%
      as_tibble() %>%
      t() %>%
      as.data.frame() %>%
      rownames_to_column(var = "HLA_gene")

    # Make sure allele columns exist
    if (!("V1" %in% names(df)) || !("V2" %in% names(df))) {
      message("JSON format issues in arcasHLA genotype JSON:\t", sample_name)
      return(
        all_HLA_genes %>%
          mutate(
            allele1_rna = NA_character_,
            allele2_rna = NA_character_,
            rna_sample_id = sample_name
          )
      )
    }

    df <- df %>%
      mutate(
        # JSON keys after transpose are usually like "A", "B", etc.
        hla_star = paste0(HLA_gene, "\\*"),
        allele1_rna = str_remove(as.character(V1), hla_star),
        allele2_rna = str_remove(as.character(V2), hla_star),
        HLA_gene = paste0("HLA-", HLA_gene)
      ) %>%
      select(HLA_gene, allele1_rna, allele2_rna)

    # Join to ensure ALL genes present (missing ones become NA)
    out <- all_HLA_genes %>%
      left_join(df, by = "HLA_gene") %>%
      mutate(rna_sample_id = sample_name)

    out
  }, error = function(e) {
    # Report and continue by returning NA rows for this sample
    message(
      "Failed parsing arcasHLA genotype JSON for sample: ", sample_name,
      " (file: ", path, ")\n",
      "  error:  ", conditionMessage(e)
    )

    all_HLA_genes %>%
      mutate(
        allele1_rna = NA_character_,
        allele2_rna = NA_character_,
        rna_sample_id = sample_name
      )
  })
}

# Build combined results robustly
rna_hla_results <- map2_dfr(
  files, sample_names,
  ~ parse_one_arcas(.x, .y, all_HLA_genes)
)

# write it out
write.csv(rna_hla_results, file = output_path, row.names = FALSE, quote = FALSE)
