#!/usr/bin/env Rscript

# Summarize a per-read HLA edit-distance table (as produced by
# make_a_table_210804_allHLAgenes.py / HLAPM_QUANTIFY_READS) into a per-gene
# read count: one row per HLA gene with the number of reads confidently
# (non-"ambiguous") and well (edit distance at or below a configurable
# threshold) assigned to it.
#
# Adapted from davenportlab/HLApm_farm_pipeline's
# 04_04_24_summarize_readcounts_script.R. Differences from that source
# script: the directory-path-derived column-name-mangling workaround is
# dropped (this pipeline's input BAM column names are already plain,
# no-directory filenames), allele/edit-distance columns are identified by
# position rather than by a "HLA" substring match, only the individual
# `dplyr`/`tidyr` packages actually used are loaded (not `tidyverse`), and
# output is genuinely tab-separated (matching the `.tsv` extension).
#
# Usage:
#   summarize_hla_readcounts.R <edit_distance.tsv> <max_edit_distance> <output.tsv>

library(dplyr)
library(tidyr)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 3) {
  stop(
    "Usage: summarize_hla_readcounts.R <edit_distance.tsv> <max_edit_distance> <output.tsv>",
    call. = FALSE
  )
}

edit_distance_path <- args[1]
max_edit_distance <- as.numeric(args[2])
output_path <- args[3]

reads_mapped <- read.table(edit_distance_path, header = TRUE)

# Allele/edit-distance columns are every column other than the three fixed
# ones make_a_table_210804_allHLAgenes.py always writes; identified by
# position (not by a "HLA" substring match) so this does not depend on the
# allele/BAM column naming convention in use.
allele_cols <- setdiff(colnames(reads_mapped), c("read_name", "gene_name_confidence", "gene_name"))

best_mapping_reads <- reads_mapped %>%
  filter(gene_name_confidence != "ambiguous") %>%
  pivot_longer(all_of(allele_cols), names_to = "allele", values_to = "edit_dist") %>%
  filter(edit_dist <= max_edit_distance) %>%
  mutate(gene_name = gsub("chr_", "", gene_name)) %>%
  select(-allele, -edit_dist) %>%
  unique()

best_mapping_reads_gene_summary <- best_mapping_reads %>%
  group_by(gene_name) %>%
  summarize(n_reads_mapping = n())

write.table(
  best_mapping_reads_gene_summary,
  file = output_path,
  sep = "\t",
  quote = FALSE,
  col.names = TRUE,
  row.names = FALSE
)
