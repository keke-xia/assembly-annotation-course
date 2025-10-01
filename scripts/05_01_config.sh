#!/usr/bin/env bash
# ---- project roots ----
ROOT="/data/users/kxia/assembly_annotation_course"
ASM_DIR="$ROOT/assemblies"
RNA_DIR="$ROOT/RNAseq_Sha"
EVAL_DIR="$ROOT/evaluations"          # store all evaluation results
REF_DIR="/data/courses/assembly-annotation-course/references"

mkdir -p "$EVAL_DIR" "$EVAL_DIR/quast" "$EVAL_DIR/busco" "$EVAL_DIR/merqury" "$EVAL_DIR/mummer"

# ---- containers ----
SIF_BUSCO="/containers/apptainer/busco_5.7.1.sif"
SIF_QUAST="/containers/apptainer/quast_5.2.0.sif"
SIF_MERQURY="/containers/apptainer/merqury_1.3.sif"
SIF_MUMMER="/containers/apptainer/mummer4_gnuplot.sif"

# ---- Arabidopsis thaliana reference ----
REF_FASTA="$REF_DIR/Arabidopsis_thaliana.TAIR10.dna.toplevel.fa"
REF_GFF3="$REF_DIR/Arabidopsis_thaliana.TAIR10.54.gff3.gz"

# ---- k-mer size for merqury ----
K=21

# ---- threads ----
THREADS="${THREADS:-8}"