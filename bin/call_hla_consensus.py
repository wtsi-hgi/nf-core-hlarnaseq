#!/usr/bin/env python3
"""
Consensus HLA calling with:
- RNA arcasHLA (multiple RNA replicates per individual)
- WGS HLA-LA (genotyping) (per WGS sample)
- Key file (mapping between RNA and WGS samples):

A re-implemented in Python and simplified version of the script:
https://github.com/davenportlab/HLApm_farm_pipeline/blob/main/03_12_24_HLA_consensus_alleles.R

Core outputs:
1) rna_wgs_summary: one row per (RNA_sample_ID, HLA_gene) with mapped WGS sample and allele sets
2) consensus_key: one row per (WGS_sample_ID, HLA_gene) with the consensus allele set

Where "WGS_sample_ID" is:
- WGS sample id if present in the key,
- The synthetic key: "NoWgsSangerID:<USUBJID>" if the sample is present in the key file
- else a synthetic id: "RNA_ONLY:<RNA_sample_ID>"
  (so RNA-only samples go into an individual group each)
"""

import argparse
import sys
from dataclasses import dataclass
from collections import Counter
from typing import Iterable, List, Optional, Set, Tuple

import pandas as pd

TRACE=frozenset([ # List of problematic locuses (WGS_sample_id, HLA-gene) to print decision tree results - for tree debugging
    #("VPS_paxgene7700033","HLA-H"),
    ("VPS_paxgene7700034","HLA-B")
])

# -------------------------
# Utilities
# -------------------------

def is_missing_token(x) -> bool:
    """True for NaN/None and common string sentinels like 'NA', ''."""
    _MISSING_STRINGS = {"", "na", "nan", "none", "null", "n/a"}
    if (x is None) or pd.isna(x):
        return True
    if isinstance(x, str):
        return x.strip().lower() in _MISSING_STRINGS
    return False


def check_required_columns(df: pd.DataFrame, required_cols:Iterable[str]) -> None:
    missing_cols = set(required_cols) - set(df.columns)
    if missing_cols:
        raise ValueError(f"Dataframe missing required columns: {sorted(missing_cols)}")

def truncate_hla_resolution(allele: str, n: int = 2) -> str:
    """Truncates HLA allele notation to required resolution. Example: '02:07:01G' -> '02:07' if n=2."""
    s = str(allele).strip()
    parts = s.split(":")
    return ":".join(parts[:n]) if len(parts) >= n else s


def normalize_hla_name(gene: str) -> str:
    """Ensure gene name contains HLA prefix, like 'HLA-A'."""
    g = str(gene).strip()
    return g if g.startswith("HLA-") else "HLA-" + g


def split_hla_gene(gene: str) -> Tuple[str, str]:
    """
    Split HLA gene string like 'DPA1*02:01:01' -> ('HLA-DPA1', '02:01:01')
    """
    t = str(gene).strip()
    if "*" not in t:
        raise ValueError(f"Unknown HLA notation of gene {t}")
    gene, allele = t.split("*", 1)
    return normalize_hla_name(gene), allele

def joinlist(column: pd.Series, delimeter:str=",") -> pd.Series:
    return column.map(
        lambda s: delimeter.join(s) if (isinstance(s, (set, frozenset, list)) and len(s) > 0 ) else "")

def is_rna_alleles_identical(rna_alleles: pd.Series) -> bool:
    """
    Check whether all RNA_alleles in a group are identical.
    """
    values = [v for v in rna_alleles]
    first = values[0]
    return all(v == first for v in values)

def rna_alleles_majority(rna_alleles: list[frozenset]) -> frozenset[str]:
    """
    Determine the top-2 most frequent RNA alleles across samples.
    TODO: this fucntion is very simple comparing to the original R code.
    Should we make it more comples (removing Q/N alleles, etc)?
    """
    counter = Counter()
    for alleles in rna_alleles:
        counter.update(alleles)
    if not counter:
        return frozenset()

    # Sort by:
    # 1) descending count
    # 2) allele name (for deterministic output)
    ranked = sorted(counter.items(), key=lambda x: (-x[1], x[0]))
    return frozenset([allele for allele, _ in ranked[:2]])


def rna_allele_consistency(
    sample_alleles: Iterable[Set[str]],
) -> tuple[str, frozenset[str]]:
    """
    Classify the consistency of allele calls across samples.

    Input: iterable of sets of allele strings. All None values shoud be removed before callign the function.
    Examples:
      [set(), set()] -> 'empty'
      [{'1','2'}, {'1','2'}] -> 'consistent'
      [{'1','2'}, {'1','2'}, set()] -> 'consistent_with_empty'
      [{'1','2'}, {'1','2'}, set(), {'1'}] -> 'consistent_with_missing'
      [{'1','2'}, {'2','3'}] -> 'inconsistent'
    """

    empties = [frozenset(x) for x in sample_alleles if len(x) == 0]
    nonempty = [frozenset(x) for x in sample_alleles if len(x) > 0]

    # Case 1: all sets empty
    if len(nonempty) == 0:
        return "rna_empty", frozenset()

    # All identical?
    unique_nonempty = frozenset(nonempty)
    if len(unique_nonempty) == 1:
        return ("rna_consistent_with_empty",nonempty[0])  if len(empties)>0 else ("rna_consistent", nonempty[0])

    # 4/5: Not all identical. Check subset-of-biggest rule.
    biggest = max(nonempty, key=len)

    # "consistent_with_missing" means: every non-empty set is a subset of the biggest one
    if all(s.issubset(biggest) for s in nonempty):
        return "rna_consistent_with_missing", biggest

    # Otherwise, there exists at least one allele that conflicts (i.e., some set has
    # an element not contained in the maximal set), which implies mutual exclusion
    # somewhere among calls.
    return "rna_inconsistent", rna_alleles_majority(nonempty)


# -------------------------
# Consensus levels (group-wise, across RNA replicates)
# -------------------------
@dataclass(frozen=True)
class ConsensusCall:
    level: int
    labels: list[str]
    alleles: Set[str]

def level1_is_wgs_id_exist(grp: pd.DataFrame) -> Optional[ConsensusCall]:
    wgs_id, gene = grp.name
    if wgs_id.startswith("RNA_ONLY:"):
        # RNA-only sample, no WGS id, nothing to compare - call is defined
        return ConsensusCall(
            level=1,
            labels=["wgs_id_missing"],
            alleles=grp["RNA_alleles"].iloc[0], # we have only one sample - copying alleles for consensus
        )
    else:
        return ConsensusCall( # Adding labels and moving call to the second level
            level=2,
            labels=["wgs_id_exist"],
            alleles=set()
        )

def level2_is_rna_consistent(grp: pd.DataFrame, call: ConsensusCall) -> Optional[ConsensusCall]:
    if call.level != 2:
        raise ValueError("This function should be called only for level 2 calls")

    rna_consistency, rna_consensus = rna_allele_consistency(grp["RNA_alleles"].to_list())
    return ConsensusCall(level=3, labels=call.labels + [rna_consistency], alleles=set(rna_consensus))


def level3_is_wgs_alleles_exist(grp: pd.DataFrame, call: ConsensusCall) -> Optional[ConsensusCall]:
    if call.level != 3:
        raise ValueError("This function should be called only for level 3 calls")
    wgs_alleles_any = any(isinstance(x, set) and len(x) > 0 for x in grp["WGS_alleles"])

    if not wgs_alleles_any:
        return ConsensusCall(level=3, labels=call.labels + ["wgs_alleles_missing"], alleles=call.alleles)
    else:
        return ConsensusCall(level=4, labels=call.labels + ["wgs_alleles_exist"], alleles=call.alleles)


def level4_rna_match_wgs(grp: pd.DataFrame, call:ConsensusCall) -> Optional[ConsensusCall]:
    if call.level != 4:
        raise ValueError("This function should be called only for level 4 calls")

    wgs_alleles = grp["WGS_alleles"].iloc[0]  # All WGS alleles are identical, so we can use the first sample
    labels = []
    if call.alleles == wgs_alleles:
        labels.append("wgs_rna_match")
        alleles = wgs_alleles
    elif len(call.alleles) == 0:
        labels.append("wgs_only")
        alleles = wgs_alleles
    else:
        if len(wgs_alleles) > 2:  # The subsequence code won't work with >2 alleles, so we have to switch back to RNA calls
            labels.append("wgs_extra_alleles")  # Flagging
            alleles = call.alleles   # Now we use RNA calls as more reliable
        else:
            alleles = wgs_alleles

        if call.alleles.issubset(wgs_alleles) or wgs_alleles.issubset(call.alleles):
            labels.append("wgs_rna_match_with_missing")
            if (len(wgs_alleles) > 2) and (len(call.alleles) == 2):
                labels.append("rna_support_2_wgs")
            else:
                labels.append("rna_support_1_wgs")
        else:
            labels.append("wgs_rna_mismatch")

    return ConsensusCall(level=4, labels=call.labels + labels, alleles=alleles)

def call_consensus_for_group(grp: pd.DataFrame):
    """
    The main fucntion for the decision tree
    Takes a group of RNA samples form the same individual and return a consensus call for it.
    """
    wgs_id, gene = grp.name
    is_trace =  (wgs_id, gene) in TRACE
    if is_trace:
        print("==== DEBUG TRACE PRINT ===", file=sys.stderr)
        print(grp, file=sys.stderr)
    call = level1_is_wgs_id_exist(grp)     # Checking existence of WGS id
    if call.level == 1:
        if is_trace: print("Consensus: ", call, file=sys.stderr)
        return call
    call = level2_is_rna_consistent(grp, call) # Checking RNA alleles consistency, returning RNA consensus
    call = level3_is_wgs_alleles_exist(grp, call) # Checking WGS alleles existence
    if call.level == 3:
        if is_trace: print("Consensus: ", call, file=sys.stderr)
        return call
    call = level4_rna_match_wgs(grp, call)  # Checking RNA alleles match WGS alleles
    if is_trace: print("Consensus: ", call, file=sys.stderr)
    return call

# -------------------------
# Main pipeline functions
# -------------------------
def load_arcashla(
    arcashla_path: str,
    truncate_fields: int = 2,
    sample_col: str = "rna_sample_id",
    gene_col: str = "HLA_gene",
) -> pd.DataFrame:
    """
    Returns df:
      RNA_sample_ID | HLA_gene | RNA_alleles (set)
    """
    df = pd.read_csv(arcashla_path, engine="python")
    required_cols = [sample_col, gene_col, "allele1_rna", "allele2_rna"]
    check_required_columns(df, required_cols)

    empty_rna = df[sample_col].isna() | (df[sample_col] == "") | (df[sample_col] == "NA")
    if empty_rna.any():
        print(f"⚠️ Found {empty_rna.sum()} RNA alleles with empty RNA_sample_ID")
        df = df.loc[ ~ empty_rna]

    df = df[required_cols]
    df["RNA_sample_ID"] = df[sample_col]

    df["HLA_gene"] = df[gene_col].map(normalize_hla_name)
    # Truncate and merge alleles into set
    df["RNA_alleles"] = df.apply(
        lambda row:
            frozenset( (truncate_hla_resolution(x, truncate_fields)
             for x in (row["allele1_rna"], row["allele2_rna"])
             if not is_missing_token(x) ) ),
        axis=1
    )
    df = df[["RNA_sample_ID", "HLA_gene", "RNA_alleles"]]
    return df

def load_hlala(
    hlala_path: str,
    truncate_fields: int = 2,
    sample_col: str = "Individual_ID",
    allele_col: str = "HLA_allele",
    multi_sep: str = ";",
    sep: str = "\t",
) -> pd.DataFrame:
    """
    Input rows like:
      Individual_ID    HLA_allele
      VPS...           DPA1*02:01:01;DPA1*02:01:08
      VPS...           A*02:07:01G

    Returns:
      WGS_sample_ID | HLA_gene | WGS_alleles (set)
    """
    df = pd.read_csv(hlala_path, sep=sep, engine='python')
    required_cols = [sample_col, allele_col]
    check_required_columns(df, required_cols)
    df = df[required_cols]

    rows: List[Tuple[str, str, str]] = []
    for sid, raw in df.itertuples(index=False):
        if is_missing_token(raw):
            continue
        wgs_id = str(sid)
        genes = [t.strip() for t in str(raw).split(multi_sep) if t.strip()]
        for gene in genes:
            if "*" not in gene:   # avoids split_hla_gene() crash on junk tokens
                raise ValueError(f"Invalid HLA allele in HLA-LA data: {gene}")
            gene_name, allele = split_hla_gene(gene)
            allele = truncate_hla_resolution(allele, truncate_fields)
            rows.append((wgs_id, gene_name, allele))

    long = pd.DataFrame(rows, columns=["WGS_sample_ID", "HLA_gene", "allele"])

    agg = (
        long.dropna(subset=["allele"]).assign(allele=lambda d: d["allele"].astype(str))
        .groupby(["WGS_sample_ID", "HLA_gene"], as_index=False)
        .agg(WGS_alleles=("allele", lambda s: set(s)))
        .sort_values(by=["WGS_sample_ID", "HLA_gene"])
        .reset_index(drop=True)
    )
    return agg

def load_rna_wgs_key(key_path: str) -> pd.DataFrame:
    """
    Key file columns required:
      sanger_sample_id_rnaseq
      sanger_sample_id_wgs
    """
    rna_wgs_key = pd.read_csv(key_path, sep="\t", engine='python')
    required_cols = ["sanger_sample_id_rnaseq", "sanger_sample_id_wgs", "USUBJID"]
    check_required_columns(rna_wgs_key, required_cols)
    rnaseq_counts = rna_wgs_key['sanger_sample_id_rnaseq'].value_counts()
    duplicates = rnaseq_counts[rnaseq_counts > 1]

    if duplicates.empty:
        print("✅ All sanger_sample_id_rnaseq values are unique.")
    else:
        print("⚠️ Found non‑unique sanger_sample_id_rnaseq values:")
        print(duplicates)

    # Fill empty WGS IDs with the prefix from the patient ID
    empty_wgs = rna_wgs_key["sanger_sample_id_wgs"].isna() | (rna_wgs_key["sanger_sample_id_wgs"] == "NA") | (rna_wgs_key["sanger_sample_id_wgs"] == "")
    rna_wgs_key.loc[empty_wgs, "sanger_sample_id_wgs"] = "NoWgsSangerID:" + rna_wgs_key["USUBJID"]

    rna_wgs_key = rna_wgs_key[required_cols].rename(columns={
            "sanger_sample_id_rnaseq": "RNA_sample_ID",
            "sanger_sample_id_wgs": "WGS_sample_ID",
        })
    return rna_wgs_key

def combine_rna_wgs(
    hla_rna: pd.DataFrame,
    hla_wgs: pd.DataFrame,
    rna_wgs_key: pd.DataFrame,
) -> pd.DataFrame:
    """
    Output per requested format:
      RNA_sample_ID | WGS_sample_ID | HLA_gene | RNA_alleles | WGS_alleles

    WGS_sample_ID and WGS_alleles may be empty.
    """
    # Adding WGS saple ID to each RNA sample
    hla_combined = hla_rna.merge(
        rna_wgs_key,
        on="RNA_sample_ID",
        how="left",
    )

    # Ensure empty WGS id if missing
    hla_combined["WGS_sample_ID"] = hla_combined["WGS_sample_ID"].where(hla_combined["WGS_sample_ID"].notna(), "")

    # Adding WS HLA genes
    hla_combined = hla_combined.merge(hla_wgs, on=["WGS_sample_ID", "HLA_gene"], how="left")

    # If WGS id exists but genotype missing, WGS_alleles will stay NaN -> set to None
    hla_combined["WGS_alleles"] = hla_combined["WGS_alleles"].where(hla_combined["WGS_alleles"].notna(), frozenset())

    hla_combined = hla_combined[["RNA_sample_ID", "WGS_sample_ID", "HLA_gene", "RNA_alleles", "WGS_alleles"]]
    # Indefinite fake individual IDs for empty WGS ids
    empty_wgs_mask = hla_combined["WGS_sample_ID"].isna() | (hla_combined["WGS_sample_ID"] == "")
    if empty_wgs_mask.any():
        ungrouped_samples = set(hla_combined.loc[empty_wgs_mask, "RNA_sample_ID" ].to_list())
        print(f"⚠️ Found {len(ungrouped_samples)} RNA samples not assigned with person_ID:")
        print(' '.join(ungrouped_samples))
        hla_combined.loc[empty_wgs_mask, "WGS_sample_ID"] = "RNA_ONLY:" + hla_combined.loc[empty_wgs_mask, "RNA_sample_ID"]
    return hla_combined.sort_values(by=['WGS_sample_ID', "RNA_sample_ID", "HLA_gene"])


def build_consensus_alleles(summary: pd.DataFrame) -> pd.DataFrame:
    """
    Groups by (WGS_id, HLA_gene) across RNA replicates and applies a decision tree to call a consensus allele set.
    """
    keys = ["WGS_sample_ID", "HLA_gene"]
    consensus = (
        summary.groupby(keys, sort=False, dropna=False)  # Grouping table by (WGS id, HLA_gene)
        .apply(call_consensus_for_group, include_groups=False)                 # Applying the function to call consensus for each group
        .rename("consensus_call")                        # Storing data in the "call" column
        .reset_index()
    )

    # Converting one 'consensus_call' column to a list of columns
    def call_level(x):   return x.level
    def call_labels(x):  return x.labels
    def call_alleles(x): return x.alleles
    consensus["consensus_level"]   = consensus["consensus_call"].map(call_level)
    consensus["consensus_labels"]  = consensus["consensus_call"].map(call_labels)
    consensus["consensus_alleles"] = consensus["consensus_call"].map(call_alleles)
    consensus = consensus.drop(columns=["consensus_call"])

    return consensus

def annotate_summary_with_consensus(summary: pd.DataFrame, consensus: pd.DataFrame) -> pd.DataFrame:
    """
    Adds per-line consensus label/level/alleles by joining on (WGS is, HLA_gene).
    """
    keys = ["WGS_sample_ID", "HLA_gene"]
    summary = summary.merge(consensus, on=keys, how="left")

    long_consensus = summary["consensus_alleles"].map(lambda x: len(x) > 2)
    if long_consensus.any():
        print("Warning: consensus calls having >2 alleles detected!:", file=sys.stderr)
        print(summary.loc[long_consensus, ["WGS_sample_ID", "HLA_gene", "consensus_alleles"]], file=sys.stderr)
    summary["consensus_alleles"] = joinlist(summary["consensus_alleles"], ",")
    summary["consensus_labels"] = joinlist(summary["consensus_labels"],"|")
    #summary["WGS_alleles"] = joinlist(summary["WGS_alleles"],",")
    #summary["RNA_alleles"] = joinlist(summary["RNA_alleles"],",")

    cols_order = ["WGS_sample_ID", "RNA_sample_ID", "HLA_gene", "consensus_alleles", "consensus_level", "consensus_labels", "RNA_alleles", "WGS_alleles",]
    summary = summary[cols_order]
    return summary.sort_values(by=["WGS_sample_ID", "RNA_sample_ID", "HLA_gene"])

# -------------------------
# Pipeline
# -------------------------

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Call consensus HLA alleles by combining RNA arcasHLA genotype calls "
            "with WGS HLA-LA genotype calls, via an RNA/WGS sample key."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--arcashla-csv",
        required=True,
        help="Combined arcasHLA RNA genotype CSV (long format, one row per HLA gene per RNA sample).",
    )
    parser.add_argument(
        "--hlala-file",
        required=True,
        help="Combined HLA-LA WGS genotype file (one allele per row).",
    )
    parser.add_argument(
        "--key-tsv",
        required=True,
        help="RNA/WGS sample key TSV with sanger_sample_id_rnaseq, sanger_sample_id_wgs, USUBJID columns.",
    )
    parser.add_argument(
        "--rna-excluded-samples",
        default=None,
        help="Optional path to a file listing RNA sample IDs (one per line) to exclude.",
    )
    parser.add_argument(
        "--wgs-excluded-samples",
        default=None,
        help="Optional path to a file listing WGS sample IDs (one per line) to exclude.",
    )
    parser.add_argument(
        "--truncate-fields",
        type=int,
        default=2,
        help="Number of colon-separated fields to keep when truncating HLA allele resolution.",
    )
    parser.add_argument(
        "--output-prefix",
        required=True,
        help=(
            "Prefix used to build output filenames: "
            "<prefix>.rna_wgs_rna-hla_with_consensus.tsv and <prefix>.rna_wgs_hla_consensus.tsv"
        ),
    )
    parser.add_argument(
        "--arcashla-sample-col",
        default="rna_sample_id",
        help="Column name for the RNA sample ID in --arcashla-csv.",
    )
    parser.add_argument(
        "--arcashla-gene-col",
        default="HLA_gene",
        help="Column name for the HLA gene in --arcashla-csv.",
    )
    parser.add_argument(
        "--hlala-sample-col",
        default="sample_id",
        help="Column name for the WGS sample ID in --hlala-file.",
    )
    parser.add_argument(
        "--hlala-allele-col",
        default="HLA_allele",
        help="Column name for the HLA allele in --hlala-file.",
    )
    parser.add_argument(
        "--hlala-sep",
        default="\t",
        help="Field separator used in --hlala-file.",
    )
    parser.add_argument(
        "--hlala-multi-sep",
        default=";",
        help="Separator between multiple alleles within a single --hlala-file allele cell (no-op for one-allele-per-row data).",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> None:
    args = parse_args(argv)

    hla_rna = load_arcashla(
        args.arcashla_csv,
        truncate_fields=args.truncate_fields,
        sample_col=args.arcashla_sample_col,
        gene_col=args.arcashla_gene_col,
    )
    # Removing bad samples
    if args.rna_excluded_samples is not None:
        with open(args.rna_excluded_samples, "r") as f:
            rna_excluded_samples = frozenset((sample.strip() for sample in f.readlines()))
        print(f"Removing {len(rna_excluded_samples)} blacklisted RNA samples")
        hla_rna = hla_rna[~hla_rna["RNA_sample_ID"].isin(rna_excluded_samples)]

    hla_wgs = load_hlala(
        args.hlala_file,
        truncate_fields=args.truncate_fields,
        sample_col=args.hlala_sample_col,
        allele_col=args.hlala_allele_col,
        multi_sep=args.hlala_multi_sep,
        sep=args.hlala_sep,
    )
    # Removing bad samples
    if args.wgs_excluded_samples is not None:
        with open(args.wgs_excluded_samples, "r") as f:
            wgs_excluded_samples = frozenset((sample.strip() for sample in f.readlines()))
        print(f"Removing WGS alleles for {len(wgs_excluded_samples)} blacklisted WGS samples")
        hla_wgs = hla_wgs[~hla_wgs["WGS_sample_ID"].isin(wgs_excluded_samples)]

    rna_wgs_key = load_rna_wgs_key(args.key_tsv)

    summary = combine_rna_wgs(hla_rna, hla_wgs, rna_wgs_key)

    hla_consensus = build_consensus_alleles(summary)
    summary_annotated = annotate_summary_with_consensus(summary, hla_consensus)
    # Remove alleles with empty consensus
    empty_consensus_mask = summary_annotated["consensus_alleles"] == ""
    summary_annotated = summary_annotated[ ~ empty_consensus_mask]
    summary_annotated.to_csv(args.output_prefix + ".rna_wgs_rna-hla_with_consensus.tsv", index=False, sep="\t")

    # Saving consensus in a separate file
    hla_consensus = hla_consensus[hla_consensus["consensus_alleles"] != frozenset()]
    hla_consensus["consensus_alleles"] = joinlist(hla_consensus["consensus_alleles"], ",")
    hla_consensus["consensus_labels"] = joinlist(hla_consensus["consensus_labels"],"|")
    hla_consensus.to_csv(args.output_prefix + ".rna_wgs_hla_consensus.tsv", index=False, sep="\t")

    # Count occurrences of each distinct consensus label
    label_counts = hla_consensus["consensus_labels"].dropna().value_counts()
    print("\nConsensus label counts:")
    print("-" * 40)
    for label, count in sorted(label_counts.items()):
        print(f"{label:<25} {count:>5}")


if __name__ == "__main__":
    main()
