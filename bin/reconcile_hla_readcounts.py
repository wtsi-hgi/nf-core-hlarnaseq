#!/usr/bin/env python3
"""
Reconcile the personalized-HLA per-read quantification
(HLAPM_STAR_QUANTIFY's edit_distance.tsv) against the local, HLA-region-
restricted featureCounts read-gene-assignment table
(COUNTS_COMMONREF_HLA's rnaseq_featurecounts.tsv), and emit a per-sample
diff table.

This is an adaptation of artifacts/scripts/compare-hla-rnaseq-readcounts.py's
read-pair reconciliation logic (kept vs. dropped classification), wired to
the two real pipeline channels rather than the legacy prototype's ad hoc
inputs. Unlike the prototype, this script:

- resolves every gene name appearing in the output (HLA and non-HLA alike)
  to a gene_id using the whole-genome --gtf, not just HLA--prefixed names
  (unlike artifacts/scripts/hijack-original-featurecounts.py's helper);
- reindexes the final per-HLA-gene count against the FULL set of
  post-filter personalized-HLA gene names, so a gene whose every read pair
  was dropped still appears with a count of 0 rather than silently
  disappearing (a gap in the prototype's value_counts()-only approach).

Logic:
1. Loads the HLA mapping table, filtering out 'ambiguous' reads and applying
   an edit distance threshold.
2. Loads the FeatureCounts table and collapses it into valid read pairs
   (both R1 and R2 present, same gene assigned to both).
3. Merges the two datasets on 'read_name'.
4. For each read pair mapped to an HLA gene in the personalized reference,
   it is KEPT if:
   - There is no matching record in the FeatureCounts table (missing_fc).
   - BOTH the personalized mapping and FeatureCounts agree the read belongs
     to an HLA gene (both_hla).
   - FeatureCounts identifies it as a non-HLA gene, but the personalized HLA
     mapping has an EQUAL or BETTER (smaller) edit distance than the
     FeatureCounts assignment (reassigned_to_hla).
   Otherwise it is dropped (dropped_due_to_better_non_hla).
"""

import argparse
import gzip
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List

import pandas as pd

description = (
    "Reconcile personalized HLA mapping results against standard RNASeq FeatureCounts "
    "assignments (the HLA-region-restricted subset) and emit a per-gene diff table.\n\n"
    "See module docstring for the full read-pair classification logic."
)


@dataclass(slots=True)
class Stats:
    processed_hla_read_pairs: int = 0
    both_hla: int = 0
    missing_fc: int = 0
    reassigned_to_hla: int = 0
    dropped_due_to_better_non_hla: int = 0


def is_hla_gene(series: pd.Series) -> pd.Series:
    return series.astype(str).str.startswith("HLA-")


def open_maybe_gzip(path: str, mode: str = "rt") -> Any:
    return gzip.open(path, mode) if path.endswith(".gz") else open(path, mode)


def parse_gtf_attributes(attr_text: str) -> Dict[str, str]:
    """
    Parse GTF attributes from the 9th column of a GTF file.

    Example input:
    gene_id "ENSG00000279928"; gene_name "DDX11L17";
    """
    attrs: Dict[str, str] = {}
    for match in re.finditer(r'(\S+)\s+"([^"]*)";', attr_text):
        key, value = match.group(1), match.group(2)
        attrs[key] = value
    return attrs


def load_gene_name_to_ids(gtf_path: str) -> Dict[str, List[str]]:
    """
    Build a gene_name -> [gene_id, ...] map from *every* gene in --gtf (not
    filtered to HLA- names, unlike hijack-original-featurecounts.py's own
    helper), using only feature_type == "gene" rows (transcript/exon rows are
    ignored here so repeated feature rows of the same gene never look like a
    spurious "duplicate").

    A gene_name may legitimately map to more than one distinct gene_id (a
    real GENCODE v50 whole-genome GTF, for example, has 484 such ambiguous
    names, including 4 HLA genes themselves - see CHANGELOG.md); this
    function no longer treats that as fatal. Each name's ids are kept in
    first-appearance-in-file order (a dict used as an insertion-ordered set,
    not a Python `set`, which does not preserve file order) so that
    resolve_gene_ids() can deterministically pick/join them.
    """
    name_to_ids: Dict[str, Dict[str, None]] = {}

    with open_maybe_gzip(gtf_path, "rt") as f:
        for line in f:
            if not line or line.startswith("#"):
                continue

            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                continue

            if fields[2] != "gene":
                continue

            attrs = parse_gtf_attributes(fields[8])
            gene_id = attrs.get("gene_id")
            gene_name = attrs.get("gene_name")
            if not gene_id or not gene_name:
                continue

            name_to_ids.setdefault(gene_name, {})[gene_id] = None

    return {name: list(ids) for name, ids in name_to_ids.items()}


def resolve_gene_ids(
    gene_names: Iterable[str],
    gene_name_to_ids: Dict[str, List[str]],
    category: str,
) -> tuple[Dict[str, str], list]:
    """
    Resolve each gene_name in gene_names to a gene_id via gene_name_to_ids,
    for a single output category ("hla" or "non_hla").

    - A gene_name absent from gene_name_to_ids (0 candidate ids) soft-fails
      to the literal string "NA" (reason=missing_gene_name).
    - A gene_name with exactly 1 candidate id resolves to it silently (no
      warning).
    - A gene_name with >1 candidate id (genuinely ambiguous in --gtf) is
      resolved differently depending on category, per the module docstring:
      - "hla": the first-appearing id is used (resolution=first_id_used).
      - "non_hla": every candidate id is kept, semicolon-joined in the same
        first-appearance order (resolution=all_ids_joined), so no id is
        silently dropped.
      Both cases produce a warning row (reason=ambiguous_gene_id).

    Returns (name -> resolved gene_id, list of warning-row dicts for this
    call). Also prints the existing batched stderr summaries (unchanged from
    before, kept for `.command.log`/interactive runs) in addition to, not
    instead of, the structured warning rows.
    """
    resolved: Dict[str, str] = {}
    warning_rows: list = []
    missing = []
    ambiguous = []

    for name in gene_names:
        ids = gene_name_to_ids.get(name, [])

        if len(ids) == 0:
            resolved[name] = "NA"
            missing.append(name)
            warning_rows.append(
                {
                    "gene_name": name,
                    "category": category,
                    "reason": "missing_gene_name",
                    "gene_ids": "",
                    "resolution": "na_placeholder",
                    "resolved_gene_id": "NA",
                }
            )
        elif len(ids) == 1:
            resolved[name] = ids[0]
        else:
            ambiguous.append(name)
            if category == "hla":
                resolved_id = ids[0]
                resolution = "first_id_used"
            else:
                resolved_id = ";".join(ids)
                resolution = "all_ids_joined"
            resolved[name] = resolved_id
            warning_rows.append(
                {
                    "gene_name": name,
                    "category": category,
                    "reason": "ambiguous_gene_id",
                    "gene_ids": ";".join(ids),
                    "resolution": resolution,
                    "resolved_gene_id": resolved_id,
                }
            )

    if missing:
        examples = ", ".join(sorted(missing)[:5])
        print(
            f"WARNING: {len(missing)} {category} gene name(s) not found in --gtf; gene_id written "
            f"as NA for these rows. Examples: {examples}",
            file=sys.stderr,
        )

    if ambiguous:
        examples = ", ".join(sorted(ambiguous)[:5])
        print(
            f"WARNING: {len(ambiguous)} {category} gene name(s) map to more than one distinct "
            f"gene_id in --gtf; see gene_id_resolution_warnings output for details. "
            f"Examples: {examples}",
            file=sys.stderr,
        )

    return resolved, warning_rows


def write_warnings_tsv(path: str, warning_rows: list) -> None:
    """
    Always write the gene-id resolution warnings TSV, even when there is
    nothing to report (header-only in that case) - a uniform, always-present
    output for downstream tooling rather than a conditionally-created file.
    """
    columns = ["gene_name", "category", "reason", "gene_ids", "resolution", "resolved_gene_id"]
    pd.DataFrame(warning_rows, columns=columns).to_csv(path, sep="\t", index=False)


def load_personref_table(path: str, max_edit_distance: int) -> pd.DataFrame:
    """
    Expected HLA file format:
      col1: read_name
      col2: gene_name_confidence
      col3: gene_name
      col4..: edit distances to different HLA alleles

    Header is expected and is read by pandas normally.
    """
    hla = pd.read_csv(path, sep="\t", dtype=str)

    if hla.shape[1] < 4:
        raise ValueError("HLA file must contain at least 4 columns")

    # Removing ambiguous reads
    hla = hla[hla["gene_name_confidence"] != "ambiguous"]

    # Finding minimum edit distance to any HLA allele.
    # Allele columns are expected to be from the 4th column onwards.
    allele_cols = [c for c in hla.columns[3:] if not c.startswith("Unnamed")]
    allele_numeric = hla[allele_cols].apply(pd.to_numeric, errors="coerce")
    hla["hla_edit_min"] = allele_numeric.min(axis=1)

    bad = hla["hla_edit_min"].isna()
    if bad.any():
        bad_reads = ", ".join(hla.loc[bad, "read_name"].head(5).astype(str))
        raise ValueError(
            f"HLA file contains rows without any numeric allele edit distance:"
            f"Read_name(s): {bad_reads}"
        )
    # Filtering for the edit distance threshold: inherited from the original R featurecount script
    hla = hla[hla["hla_edit_min"] <= max_edit_distance]

    # Keep only the columns we need
    hla = hla[["read_name", "gene_name", "hla_edit_min"]].rename(columns={"gene_name": "hla_gene"})

    # Raise an error if duplicates exist.
    # The expected format is one row per read pair.
    if hla.duplicated(subset=["read_name"]).any():
        duplicate_reads = ", ".join(hla.loc[hla.duplicated(subset=["read_name"]), "read_name"].head(5).astype(str))
        raise ValueError(f"Duplicate read names found in personalized reference reads file: {duplicate_reads}")
    return hla


def collapse_featurecounts_pairs(featurecounts: pd.DataFrame) -> pd.DataFrame:
    """
    Collapse FeatureCounts rows into valid read pairs.

    Keep only groups that:
    - have exactly 2 rows
    - have directions R1 and R2
    - have the same gene on both mates

    Singleton mate groups are dropped, logged to stderr.
    """
    grp = featurecounts.groupby("read_name", sort=False)

    group_size = grp.size().rename("n_rows")
    dropped_featurecounts_singletons = int((group_size == 1).sum())
    if dropped_featurecounts_singletons > 0:
        print(f"Dropped {dropped_featurecounts_singletons} singletons from FeatureCounts reads", file=sys.stderr)

    direction_nunique = grp["direction"].nunique().rename("direction_nunique")
    gene_nunique = grp["fc_gene"].nunique().rename("gene_nunique")
    edit_sum = grp["fc_edit_distance"].sum().rename("fc_edit_sum")
    first_gene = grp["fc_gene"].first().rename("fc_gene")

    # Check that directions are exactly R1/R2
    direction_flags = featurecounts.assign(
        is_r1=featurecounts["direction"].eq("R1"),
        is_r2=featurecounts["direction"].eq("R2"),
    ).groupby("read_name", sort=False)[["is_r1", "is_r2"]].any()

    summary = pd.concat(
        [group_size, direction_nunique, gene_nunique, edit_sum, first_gene, direction_flags],
        axis=1,
    ).reset_index()

    valid = (
        (summary["n_rows"] == 2)
        & (summary["direction_nunique"] == 2)
        & summary["is_r1"]
        & summary["is_r2"]
        & (summary["gene_nunique"] == 1)
    )

    pairs = summary.loc[valid, ["read_name", "fc_gene", "fc_edit_sum"]].copy()
    return pairs


def load_filtered_featurecounts(path: str) -> pd.DataFrame:
    """
    Expected FeatureCounts-derived format:
      read_name  direction  gene_name  edit_distance

    Header is expected and is read by pandas normally.
    """
    featurecounts = pd.read_csv(path, sep="\t").rename(
        columns={"gene_name": "fc_gene", "edit_distance": "fc_edit_distance"}
    )
    return collapse_featurecounts_pairs(featurecounts)


def reconcile(personref: pd.DataFrame, fc_pairs: pd.DataFrame) -> tuple[pd.Series, pd.Series, Stats]:
    """
    Classify every personalized-HLA read pair as kept (missing_fc, both_hla,
    or reassigned_to_hla) or dropped (dropped_due_to_better_non_hla), then
    build:

    - hla_counts: gene_name -> reconciled kept read-pair count, reindexed
      against the FULL set of post-filter personalized-HLA gene names (0 for
      genes with no kept reads - the "dropped-to-zero" fix over the
      prototype's value_counts()-only approach, which silently omitted such
      genes entirely).
    - fc_negative_counts: fc_gene -> negative count of read pairs reassigned
      away from that non-HLA gene to HLA (never zero-valued: only genes with
      >=1 reassigned read pair appear at all).
    """
    stats = Stats()
    personref_is_not_hla = ~is_hla_gene(personref["hla_gene"])
    if personref_is_not_hla.any():
        raise ValueError(
            f"Found {personref_is_not_hla.sum()} reads that have no HLA gene assigned in the "
            "personalized reference table. This is unexpected."
        )

    all_hla_genes = personref["hla_gene"].unique()

    merged = personref.merge(fc_pairs, on="read_name", how="left")
    stats.processed_hla_read_pairs = len(merged)

    missing_fc = merged["fc_gene"].isna()
    stats.missing_fc = int(missing_fc.sum())

    fc_is_hla = is_hla_gene(merged["fc_gene"])
    stats.both_hla = int(fc_is_hla.sum())

    # NOTE: hla_edit_min is compared against fc_edit_sum. This assumes
    # hla_edit_min also represents the total edit distance for the read pair.
    fc_is_not_hla = ~missing_fc & ~fc_is_hla
    fc_reassign_to_hla = fc_is_not_hla & (merged["hla_edit_min"] <= merged["fc_edit_sum"])
    stats.reassigned_to_hla = int(fc_reassign_to_hla.sum())

    reassign_to_non_hla = fc_is_not_hla & (merged["hla_edit_min"] > merged["fc_edit_sum"])
    stats.dropped_due_to_better_non_hla = int(reassign_to_non_hla.sum())

    total_assign_to_hla = missing_fc | fc_is_hla | fc_reassign_to_hla

    kept_hla = merged.loc[total_assign_to_hla, "hla_gene"]
    hla_counts = kept_hla.value_counts().reindex(all_hla_genes, fill_value=0).sort_index()

    overruled_fc = merged.loc[fc_reassign_to_hla, "fc_gene"]
    fc_negative_counts = -overruled_fc.value_counts().sort_index()

    return hla_counts, fc_negative_counts, stats


def build_output_rows(
    hla_counts: pd.Series,
    fc_negative_counts: pd.Series,
    fc_pairs: pd.DataFrame,
    gene_name_to_ids: Dict[str, List[str]],
) -> tuple[pd.DataFrame, list]:
    """
    Build the final output table:
      gene_id  gene_name  category  original_fc_count  personalized_count  diff

    - HLA rows: one per post-filter personalized-HLA gene name (hla_counts'
      full index, including 0-count genes).
    - non-HLA rows: one per fc_gene with >=1 read pair reassigned away to
      HLA (fc_negative_counts' index) - never a "0 diff" row for an
      untouched non-HLA gene.

    gene_id resolution is category-aware (see resolve_gene_ids()), called
    once per category since hla_counts.index/fc_negative_counts.index are
    already exactly the HLA/non-HLA partition. Returns (output table, list
    of gene-id-resolution warning-row dicts from both calls, combined).
    """
    fc_pair_counts = fc_pairs["fc_gene"].value_counts()

    hla_gene_ids, hla_warning_rows = resolve_gene_ids(
        sorted(hla_counts.index), gene_name_to_ids, category="hla"
    )
    non_hla_gene_ids, non_hla_warning_rows = resolve_gene_ids(
        sorted(fc_negative_counts.index), gene_name_to_ids, category="non_hla"
    )
    gene_ids = {**hla_gene_ids, **non_hla_gene_ids}
    warning_rows = hla_warning_rows + non_hla_warning_rows

    rows = []
    for gene_name in sorted(hla_counts.index):
        original_fc_count = int(fc_pair_counts.get(gene_name, 0))
        personalized_count = int(hla_counts[gene_name])
        rows.append(
            {
                "gene_id": gene_ids[gene_name],
                "gene_name": gene_name,
                "category": "hla",
                "original_fc_count": original_fc_count,
                "personalized_count": personalized_count,
                "diff": personalized_count - original_fc_count,
            }
        )

    for gene_name in sorted(fc_negative_counts.index):
        original_fc_count = int(fc_pair_counts.get(gene_name, 0))
        diff = int(fc_negative_counts[gene_name])
        rows.append(
            {
                "gene_id": gene_ids[gene_name],
                "gene_name": gene_name,
                "category": "non_hla",
                "original_fc_count": original_fc_count,
                "personalized_count": "NA",
                "diff": diff,
            }
        )

    output_table = pd.DataFrame(
        rows, columns=["gene_id", "gene_name", "category", "original_fc_count", "personalized_count", "diff"]
    )
    return output_table, warning_rows


def print_stats(stats: Stats) -> None:
    print(f"processed_hla_read_pairs\t{stats.processed_hla_read_pairs}", file=sys.stderr)
    print(f"both_hla\t{stats.both_hla}", file=sys.stderr)
    print(f"missing_fc\t{stats.missing_fc}", file=sys.stderr)
    print(f"reassigned_to_hla\t{stats.reassigned_to_hla}", file=sys.stderr)
    print(f"dropped_due_to_better_non_hla\t{stats.dropped_due_to_better_non_hla}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=description,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("featurecounts", help="counts_commonref_hla per-read gene-assignment TSV (read_name, direction, gene_name, edit_distance)")
    parser.add_argument("personalized", help="HLAPM_STAR_QUANTIFY per-read edit_distance.tsv")
    parser.add_argument("--gtf", required=True, help="Whole-genome reference GTF used to resolve gene_name -> gene_id")
    parser.add_argument(
        "--max-edit-distance",
        type=int,
        default=16,
        help="Drop personalized-HLA reads that have a bigger edit distance than this threshold",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="-",
        help="Output path, or '-' for stdout",
    )
    parser.add_argument(
        "--warnings-output",
        required=True,
        help="Path to write the gene-id resolution warnings TSV (always written, header-only when empty)",
    )
    args = parser.parse_args()

    print("Loading GTF gene mappings:", args.gtf, file=sys.stderr)
    gene_name_to_ids = load_gene_name_to_ids(args.gtf)

    print("Loading personalized HLA reads:", args.personalized, file=sys.stderr)
    personref = load_personref_table(args.personalized, args.max_edit_distance)

    print("Loading FeatureCounts:", args.featurecounts, file=sys.stderr)
    fc_pairs = load_filtered_featurecounts(args.featurecounts)

    hla_counts, fc_negative_counts, stats = reconcile(personref, fc_pairs)
    output_table, warning_rows = build_output_rows(hla_counts, fc_negative_counts, fc_pairs, gene_name_to_ids)

    out_handle = sys.stdout if args.output == "-" else open(args.output, "w", encoding="utf-8")
    try:
        output_table.to_csv(out_handle, sep="\t", index=False)
    finally:
        if out_handle is not sys.stdout:
            out_handle.close()

    write_warnings_tsv(args.warnings_output, warning_rows)

    print_stats(stats)


if __name__ == "__main__":
    main()
