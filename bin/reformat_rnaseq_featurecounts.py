#!/usr/bin/env python3

import argparse
import gzip
import re
import sys

def open_maybe_gzip(path, mode="rt"):
    if path.endswith(".gz"):
        return gzip.open(path, mode)
    return open(path, mode)


def parse_gtf_attributes(attr_text):
    """
    Parse GTF attributes like:
    gene_id "ENSG00000279928"; gene_name "DDX11L17";
    """
    attrs = {}
    for match in re.finditer(r'(\S+)\s+"([^"]*)";', attr_text):
        key, value = match.group(1), match.group(2)
        attrs[key] = value
    return attrs


def load_gene_names_from_gtf(gtf_path):
    """
    Build gene_id -> gene_name from GTF.
    Prefer rows with feature type 'gene', but other rows also work.
    """
    gene_id_to_name = {}

    with open_maybe_gzip(gtf_path, "rt") as f:
        for line in f:
            if not line or line.startswith("#"):
                continue

            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                continue

            feature_type = fields[2]
            attrs = parse_gtf_attributes(fields[8])

            gene_id = attrs.get("gene_id")
            if not gene_id:
                continue

            gene_name = attrs.get("gene_name")

            if gene_name:
                # Prefer gene rows if possible, otherwise keep first seen name
                if gene_id not in gene_id_to_name or feature_type == "gene":
                    gene_id_to_name[gene_id] = gene_name

    return gene_id_to_name


def flag_to_mate_direction(flag):
    """
    SAM flag bits:
      0x40 = first in pair
      0x80 = second in pair
    """
    if flag & 0x40:
        return "R1"
    if flag & 0x80:
        return "R2"
    return "NA"


def parse_optional_fields(fields):
    """
    Parse SAM optional fields like:
      NH:i:1
      XT:Z:ENSG00000231389
      nM:i:1
      NM:i:1

    Returns dict tag -> value string
    """
    result = {}
    for field in fields:
        parts = field.split(":", 2)
        if len(parts) == 3:
            tag, typ, value = parts
            result[tag] = value
    return result


def convert_assignments(assignments_path, gtf_path, output_path):
    print("Parsing reads: ", assignments_path, file=sys.stderr)
    gene_id_to_name = load_gene_names_from_gtf(gtf_path)
    with open_maybe_gzip(assignments_path, "rt") as fin, open(output_path, "wt") as fout:
        fout.write("read_name\tdirection\tgene_name\tedit_distance\n")

        for line_num, line in enumerate(fin, start=1):
            line = line.rstrip("\n")
            if not line:
                print(f"WARNING: empty line {line_num}", file=sys.stderr)
                continue

            fields = line.split("\t")
            if len(fields) < 12:
                raise ValueError(f"WARNING: skipping malformed line {line_num}")

            read_id = fields[0]

            try:
                flag = int(fields[1])
            except ValueError:
                raise ValueError(f"WARNING: invalid FLAG on line {line_num}")

            direction = flag_to_mate_direction(flag)
            optional = parse_optional_fields(fields[11:])

            gene_id = optional.get("XT")
            if not gene_id:
                raise ValueError(f"WARNING: missing XT tag on line {line_num}")
            gene_name = gene_id_to_name.get(gene_id, gene_id)

            # STAR BAM uses nM, but standard SAM usually uses NM - checking for both
            edit_distance = optional.get("nM", optional.get("NM", 100))

            fout.write(f"{read_id}\t{direction}\t{gene_name}\t{edit_distance}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Convert featureCounts assigned-read output into a table for reads quantification: read, gene name, edit distance."
    )
    parser.add_argument(
        "-i", "--input",
        required=True,
        help="Input featureCounts assignment file (SAM-like tab-delimited text, optionally .gz)"
    )
    parser.add_argument(
        "-g", "--gtf",
        required=True,
        help="GTF annotation file used for RNA-seq (optionally .gz)"
    )
    parser.add_argument(
        "-o", "--output",
        required=True,
        help="Output TSV file"
    )

    args = parser.parse_args()
    convert_assignments(args.input, args.gtf, args.output)


if __name__ == "__main__":
    main()