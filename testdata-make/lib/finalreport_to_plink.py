#!/usr/bin/env python3
"""Convert Illumina/Nexus FinalReport files into PLINK BED/BIM/FAM for HIBAG.

The GEO Nexus FinalReport for GSE96790 (NA12878 / GM12878, HumanOmniExpress-24
v1.0) carries no genotype calls -- its columns are:

    Sample Name  Sample ID  SNP Name  Chr  Position
    Log R Ratio  B Allele Freq  GC Score  SNP

so genotypes are derived from the B Allele Freq (BAF) clusters together with
the A/B allele pair in the ``SNP`` column.  This is an approximation of
GenomeStudio's clustering; SNPs falling between the BAF clusters, or below the
GC Score threshold, are written as missing.

Genotypes are emitted as PLINK 1 binary, which ``HIBAG::hlaBED2Geno()`` reads
directly.  HIBAG reports the dosage of the first ``.bim`` allele (A1), so the
Illumina A allele is written as A1 and the B allele as A2.
"""

from __future__ import annotations

import argparse
import gzip
import sys
from typing import Dict, List, TextIO, Tuple

# PLINK 1 binary 2-bit genotype codes.
HOM_A1 = 0b00
MISSING = 0b01
HET = 0b10
HOM_A2 = 0b11

BED_MAGIC = bytes([0x6C, 0x1B, 0x01])  # magic bytes + SNP-major mode

REQUIRED_COLUMNS = (
    "SNP Name",
    "Chr",
    "Position",
    "B Allele Freq",
    "GC Score",
    "SNP",
)

VALID_ALLELES = frozenset("ACGT")
AMBIGUOUS_PAIRS = (frozenset("AT"), frozenset("CG"))


class ReportError(RuntimeError):
    """Raised when a FinalReport does not have the expected structure."""


def parse_region(text: str) -> Tuple[str, int, int] | None:
    """Parse ``CHR:START-END`` into a tuple, or ``None`` for ``all``."""
    if text.strip().lower() == "all":
        return None
    try:
        chrom, span = text.split(":", 1)
        start_text, end_text = span.split("-", 1)
        start, end = int(start_text), int(end_text)
    except ValueError:
        raise SystemExit(
            f"ERROR: could not parse region {text!r}; expected CHR:START-END or 'all'"
        )
    if start > end:
        raise SystemExit(f"ERROR: region start is after region end: {text!r}")
    return normalise_chrom(chrom), start, end


def normalise_chrom(chrom: str) -> str:
    chrom = chrom.strip()
    if chrom.lower().startswith("chr"):
        chrom = chrom[3:]
    return chrom


def open_report(path: str) -> TextIO:
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "rt", encoding="utf-8", errors="replace")


def read_header(handle: TextIO, path: str) -> Dict[str, int]:
    """Skip the ``[Header]`` block and return a column-name -> index map.

    Columns are resolved by name so that a differently ordered report fails
    loudly here instead of being silently misparsed.
    """
    for line in handle:
        if line.strip() == "[Data]":
            break
    else:
        raise ReportError(f"{path}: no [Data] section found")

    header_line = handle.readline()
    if not header_line:
        raise ReportError(f"{path}: [Data] section has no column header")

    columns = {name: index for index, name in enumerate(header_line.rstrip("\n").split("\t"))}
    missing = [name for name in REQUIRED_COLUMNS if name not in columns]
    if missing:
        raise ReportError(f"{path}: missing expected column(s): {', '.join(missing)}")
    return columns


def parse_alleles(field: str) -> Tuple[str, str] | None:
    """Parse an Illumina ``[A/B]`` allele field into ``(A1, A2)``.

    Returns ``None`` for indel (``[D/I]``) and any other non-SNP entry.
    """
    field = field.strip()
    if len(field) != 5 or field[0] != "[" or field[2] != "/" or field[4] != "]":
        return None
    a1, a2 = field[1], field[3]
    if a1 not in VALID_ALLELES or a2 not in VALID_ALLELES or a1 == a2:
        return None
    return a1, a2


def call_genotype(baf: float, gc_score: float, thresholds: argparse.Namespace) -> int:
    """Call a genotype from B Allele Freq, or return ``MISSING``."""
    if gc_score < thresholds.gc_min:
        return MISSING
    if baf < thresholds.baf_hom_a:
        return HOM_A1
    if baf > thresholds.baf_hom_b:
        return HOM_A2
    if thresholds.baf_het_lo < baf < thresholds.baf_het_hi:
        return HET
    return MISSING


class Stats:
    def __init__(self) -> None:
        self.rows = 0
        self.in_region = 0
        self.dropped_unmapped = 0
        self.dropped_non_snp = 0
        self.dropped_duplicate = 0
        self.dropped_malformed = 0
        self.hom_a1 = 0
        self.het = 0
        self.hom_a2 = 0
        self.missing_gc = 0
        self.missing_baf = 0


def parse_report(
    path: str, region: Tuple[str, int, int] | None, thresholds: argparse.Namespace
) -> Tuple[Dict[str, Tuple[str, int, str, str, int]], Stats]:
    """Stream one FinalReport, returning ``rsid -> (chrom, pos, a1, a2, code)``."""
    stats = Stats()
    snps: Dict[str, Tuple[str, int, str, str, int]] = {}
    seen_positions: set[Tuple[str, int]] = set()

    with open_report(path) as handle:
        columns = read_header(handle, path)
        i_name = columns["SNP Name"]
        i_chr = columns["Chr"]
        i_pos = columns["Position"]
        i_baf = columns["B Allele Freq"]
        i_gc = columns["GC Score"]
        i_snp = columns["SNP"]
        widest = max(columns.values())

        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) <= widest:
                stats.dropped_malformed += 1
                continue
            stats.rows += 1

            chrom = normalise_chrom(fields[i_chr])
            try:
                position = int(fields[i_pos])
            except ValueError:
                stats.dropped_malformed += 1
                continue

            if region is not None:
                if chrom != region[0] or not region[1] <= position <= region[2]:
                    continue
            if position <= 0:
                stats.dropped_unmapped += 1
                continue
            stats.in_region += 1

            alleles = parse_alleles(fields[i_snp])
            if alleles is None:
                stats.dropped_non_snp += 1
                continue

            rsid = fields[i_name].strip()
            key = (chrom, position)
            if rsid in snps or key in seen_positions:
                stats.dropped_duplicate += 1
                continue

            try:
                baf = float(fields[i_baf])
                gc_score = float(fields[i_gc])
            except ValueError:
                stats.dropped_malformed += 1
                continue

            code = call_genotype(baf, gc_score, thresholds)
            if code == HOM_A1:
                stats.hom_a1 += 1
            elif code == HET:
                stats.het += 1
            elif code == HOM_A2:
                stats.hom_a2 += 1
            elif gc_score < thresholds.gc_min:
                stats.missing_gc += 1
            else:
                stats.missing_baf += 1

            seen_positions.add(key)
            snps[rsid] = (chrom, position, alleles[0], alleles[1], code)

    if not snps:
        raise ReportError(f"{path}: no usable SNPs found in the requested region")
    return snps, stats


def write_plink(
    prefix: str,
    sample_ids: List[str],
    variants: List[Tuple[str, str, int, str, str]],
    genotypes: List[List[int]],
) -> None:
    """Write ``.bed`` (SNP-major), ``.bim`` and ``.fam``."""
    n_samples = len(sample_ids)
    bytes_per_variant = (n_samples + 3) // 4

    with open(f"{prefix}.bed", "wb") as bed:
        bed.write(BED_MAGIC)
        for row in genotypes:
            packed = bytearray(bytes_per_variant)
            for index, code in enumerate(row):
                packed[index // 4] |= code << (2 * (index % 4))
            bed.write(packed)

    with open(f"{prefix}.bim", "w", encoding="utf-8") as bim:
        for chrom, rsid, position, a1, a2 in variants:
            bim.write(f"{chrom}\t{rsid}\t0\t{position}\t{a1}\t{a2}\n")

    with open(f"{prefix}.fam", "w", encoding="utf-8") as fam:
        for sample_id in sample_ids:
            # Sex 2: NA12878 is female. Phenotype -9: unknown.
            fam.write(f"{sample_id} {sample_id} 0 0 2 -9\n")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert Illumina/Nexus FinalReport files to PLINK BED/BIM/FAM for HIBAG.",
    )
    parser.add_argument(
        "--report", action="append", required=True, metavar="FILE",
        help="FinalReport file (.txt or .txt.gz). Repeat for multiple samples.",
    )
    parser.add_argument(
        "--sample-id", action="append", required=True, metavar="ID",
        help="PLINK sample ID. Repeat once per --report, in the same order.",
    )
    parser.add_argument(
        "--out-prefix", required=True, metavar="PREFIX",
        help="Output prefix; writes PREFIX.bed, PREFIX.bim, PREFIX.fam.",
    )
    parser.add_argument(
        "--region", default="6:25000000-34000000", metavar="CHR:START-END",
        help="Region to keep, or 'all' (default: %(default)s).",
    )
    parser.add_argument("--log", metavar="FILE", help="Also write the summary here.")
    parser.add_argument(
        "--gc-min", type=float, default=0.15,
        help="Minimum GC Score; below this a SNP is called missing (default: %(default)s).",
    )
    parser.add_argument("--baf-hom-a", type=float, default=0.15, help="BAF below this is hom A1.")
    parser.add_argument("--baf-het-lo", type=float, default=0.35, help="Lower BAF bound for het.")
    parser.add_argument("--baf-het-hi", type=float, default=0.65, help="Upper BAF bound for het.")
    parser.add_argument("--baf-hom-b", type=float, default=0.85, help="BAF above this is hom A2.")
    return parser


def main(argv: List[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if len(args.report) != len(args.sample_id):
        raise SystemExit(
            f"ERROR: got {len(args.report)} --report but {len(args.sample_id)} --sample-id; "
            "they must be given in matching pairs"
        )
    if not args.baf_hom_a <= args.baf_het_lo < args.baf_het_hi <= args.baf_hom_b:
        raise SystemExit(
            "ERROR: BAF thresholds must satisfy "
            "baf-hom-a <= baf-het-lo < baf-het-hi <= baf-hom-b"
        )

    region = parse_region(args.region)

    try:
        parsed = [parse_report(path, region, args) for path in args.report]
    except ReportError as error:
        raise SystemExit(f"ERROR: {error}")

    per_report = [snps for snps, _ in parsed]

    # Keep only SNPs typed consistently across every report.
    shared = set(per_report[0])
    for snps in per_report[1:]:
        shared &= set(snps)
    reference = per_report[0]
    inconsistent = 0
    for rsid in sorted(shared):
        chrom, position, a1, a2, _ = reference[rsid]
        for snps in per_report[1:]:
            if snps[rsid][:4] != (chrom, position, a1, a2):
                inconsistent += 1
                shared.discard(rsid)
                break
    if not shared:
        raise SystemExit("ERROR: no SNPs are shared across all reports")

    ordered = sorted(shared, key=lambda rsid: reference[rsid][1])
    variants: List[Tuple[str, str, int, str, str]] = []
    genotypes: List[List[int]] = []
    ambiguous_strand = 0
    for rsid in ordered:
        chrom, position, a1, a2, _ = reference[rsid]
        variants.append((chrom, rsid, position, a1, a2))
        genotypes.append([snps[rsid][4] for snps in per_report])
        if frozenset((a1, a2)) in AMBIGUOUS_PAIRS:
            ambiguous_strand += 1

    write_plink(args.out_prefix, args.sample_id, variants, genotypes)

    lines = [
        "FinalReport -> PLINK conversion for HIBAG",
        "",
        "Genotypes are DERIVED from B Allele Freq, not read from GenomeStudio",
        "calls: the Nexus FinalReport contains no GType/Allele columns. SNPs",
        "between the BAF clusters or below the GC Score cutoff are written as",
        "missing.",
        "",
        f"region:            {args.region}",
        f"gc score minimum:  {args.gc_min}",
        f"baf thresholds:    hom-A < {args.baf_hom_a}, "
        f"het {args.baf_het_lo}-{args.baf_het_hi}, hom-B > {args.baf_hom_b}",
        "",
    ]
    for path, sample_id, (_, stats) in zip(args.report, args.sample_id, parsed):
        called = stats.hom_a1 + stats.het + stats.hom_a2
        missing = stats.missing_gc + stats.missing_baf
        total = called + missing
        rate = (100.0 * missing / total) if total else 0.0
        lines += [
            f"[{sample_id}] {path}",
            f"  rows read:           {stats.rows}",
            f"  in region:           {stats.in_region}",
            f"  dropped, unmapped:   {stats.dropped_unmapped}",
            f"  dropped, non-SNP:    {stats.dropped_non_snp}",
            f"  dropped, duplicate:  {stats.dropped_duplicate}",
            f"  dropped, malformed:  {stats.dropped_malformed}",
            f"  called hom-A1:       {stats.hom_a1}",
            f"  called het:          {stats.het}",
            f"  called hom-A2:       {stats.hom_a2}",
            f"  missing, low GC:     {stats.missing_gc}",
            f"  missing, BAF gap:    {stats.missing_baf}",
            f"  missing rate:        {rate:.2f}%",
            "",
        ]
    if len(args.report) > 1:
        lines.append(f"dropped, inconsistent across reports: {inconsistent}")
    lines += [
        f"samples written:   {len(args.sample_id)}",
        f"variants written:  {len(variants)}",
        f"strand-ambiguous:  {ambiguous_strand} (A/T or C/G)",
        "",
        "Strand-ambiguous SNPs cannot be resolved by allele comparison alone;",
        "HIBAG::hlaGenoSwitchStrand() handles the rest at prediction time.",
        "",
        f"wrote {args.out_prefix}.bed / .bim / .fam",
    ]
    summary = "\n".join(lines)

    print(summary)
    if args.log:
        with open(args.log, "w", encoding="utf-8") as handle:
            handle.write(summary + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
