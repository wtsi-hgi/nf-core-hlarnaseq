# `ARCASHLA_GENOTYPE` test fixture

`HLA_SIGNAL_R1.fastq.gz` / `HLA_SIGNAL_R2.fastq.gz` are a small, real subset
of properly-paired, primary reads from
`testdata-make/hlarnases-testdata/rnaseq/hla_bam/SRR3192657_GSM2072350_ENCLB038ZZZ.chr6_hla.GRCh38.bam`
(already restricted to the chr6 HLA region upstream), subsampled with
`samtools view -f 2 -F 256 -s 42.003` (~2,600 read pairs) and converted to
paired FASTQ with `samtools collate` + `samtools fastq`.

Unlike the pipeline's own tiny `-profile test` fixture
(`tests/fixtures/fastq/`), which is a placeholder with no read content at
all, this fixture carries real HLA-region signal - enough for
`arcasHLA genotype` to run its full alignment/genotyping path (not just
exit early on empty input) in
`modules/local/arcashla/genotype/tests/main.nf.test`. It is not large enough
to guarantee stable, version-independent allele calls, so that test asserts
the process succeeds and reports a real tool version rather than specific
genotype output content.
