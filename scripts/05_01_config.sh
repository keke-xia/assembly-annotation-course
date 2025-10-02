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
REF_GFF3="$REF_DIR/Arabidopsis_thaliana.TAIR10.57.gff3"

# ---- k-mer size for merqury ----
K=21

# ---- threads ----
THREADS="${THREADS:-8}"

# ---- BUSCO offline download path & fixed lineage ----
BUSCO_DL="$ROOT/busco_downloads"
BUSCO_LINEAGE="brassicales_odb10"
# ---- explicit assembly inputs ----
FLYE_ASM="$ASM_DIR/flye/assembly.fasta"
HIFIASM_ASM="$ASM_DIR/hifiasm/asm.bp.p_ctg.fa"
LJA_ASM="$ASM_DIR/lja/assembly.fasta"
TRINITY_ASM="$ASM_DIR/trinity/Trinity.fasta"

# 必须评估的 genome assemblies

ASSEMBLIES=( "$ASM_DIR/flye/assembly.fasta" \
             "$ASM_DIR/hifiasm/asm.bp.p_ctg.fa" \
             "$ASM_DIR/lja/assembly.fasta" )

# Transcriptome assemblies
TRANSCRIPTOMES=( "$TRINITY_ASM" )

# ---- labels for outputs ----
# 给每个输入文件一个“想要的名字”
declare -A ASM_LABEL
ASM_LABEL["$FLYE_ASM"]="flye"
ASM_LABEL["$HIFIASM_ASM"]="hifiasm_primary"
ASM_LABEL["$LJA_ASM"]="lja"
ASM_LABEL["$TRINITY_ASM"]="trinity"

