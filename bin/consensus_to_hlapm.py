#!/usr/bin/env python3
"""
Convert hla_consensus.rna_wgs_hla_consensus.tsv into per-individual HLApm
input TSVs.

Input (produced by call_hla_consensus.py, see HLA_CONSENSUS): one row per
(WGS_sample_ID, HLA_gene) with columns WGS_sample_ID, HLA_gene,
consensus_level, consensus_labels, consensus_alleles. HLA_gene carries an
"HLA-" prefix (e.g. "HLA-DRB1"); consensus_alleles is a comma-joined set of
truncated, unprefixed allele strings (e.g. "11:50Q,01:136"). WGS_sample_ID may
be a synthetic "RNA_ONLY:<rna_id>" group for RNA samples with no matched WGS
sample.

Output: one 2-column TSV per individual (WGS_sample_ID, including synthetic
"RNA_ONLY:<id>" groups), named "<individual_ID>.tsv", with a header row
"individual_ID\tHLA_allele" followed by one row per allele in the shape
HLApm's bulkRNA_build_personalized_HLA_ref() expects: unprefixed locus, e.g.
"A*11:50".

Locus filtering is an explicit allow-list (--allowed-loci): any HLA_gene
whose locus (with the "HLA-" prefix stripped) is not in the allow-list is
simply omitted from the per-individual TSVs. No separate audit/log file is
written for excluded loci.
"""

import argparse
import csv
import os
import sys
from typing import List, Optional


def normalize_locus(hla_gene: str) -> str:
    """Strip a leading 'HLA-' prefix from a gene name, e.g. 'HLA-DRB1' -> 'DRB1'."""
    gene = str(hla_gene).strip()
    return gene[len("HLA-"):] if gene.startswith("HLA-") else gene


def parse_allowed_loci(allowed_loci: str) -> frozenset:
    return frozenset(locus.strip() for locus in allowed_loci.split(",") if locus.strip())


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert an hla_consensus.rna_wgs_hla_consensus.tsv-shaped file into "
            "one per-individual, 2-column HLApm input TSV per WGS_sample_ID "
            "group, filtered by an explicit locus allow-list."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--consensus-tsv",
        required=True,
        help="Path to the hla_consensus.rna_wgs_hla_consensus.tsv-shaped input file.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory to write per-individual HLApm input TSVs into (created if missing).",
    )
    parser.add_argument(
        "--allowed-loci",
        required=True,
        help=(
            "Comma-separated allow-list of HLA loci, without the 'HLA-' prefix "
            "(e.g. 'A,B,C,DRB1'). HLA genes whose locus is not in this list are "
            "omitted from the generated TSVs."
        ),
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> None:
    args = parse_args(argv)
    allowed_loci = parse_allowed_loci(args.allowed_loci)

    os.makedirs(args.output_dir, exist_ok=True)

    per_individual: dict[str, List[str]] = {}
    with open(args.consensus_tsv, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        required_cols = {"WGS_sample_ID", "HLA_gene", "consensus_alleles"}
        missing_cols = required_cols - set(reader.fieldnames or [])
        if missing_cols:
            raise ValueError(f"Consensus TSV missing required columns: {sorted(missing_cols)}")

        for row in reader:
            individual_id = row["WGS_sample_ID"].strip()
            if not individual_id:
                continue

            locus = normalize_locus(row["HLA_gene"])
            if locus not in allowed_loci:
                continue

            alleles = [allele.strip() for allele in row["consensus_alleles"].split(",") if allele.strip()]
            for allele in alleles:
                per_individual.setdefault(individual_id, []).append(f"{locus}*{allele}")

    if not per_individual:
        print(
            "Warning: no individuals with allow-listed loci found; no HLApm input TSVs written.",
            file=sys.stderr,
        )

    for individual_id, hla_alleles in sorted(per_individual.items()):
        out_path = os.path.join(args.output_dir, f"{individual_id}.tsv")
        with open(out_path, "w", newline="") as out_fh:
            writer = csv.writer(out_fh, delimiter="\t")
            writer.writerow(["individual_ID", "HLA_allele"])
            for hla_allele in hla_alleles:
                writer.writerow([individual_id, hla_allele])


if __name__ == "__main__":
    main()
