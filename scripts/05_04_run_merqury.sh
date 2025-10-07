#!/usr/bin/env bash
#SBATCH --job-name=merqury_per_asm
#SBATCH --partition=pibu_el8
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=1-00:00:00
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course

# 仅修改了以下变量 ↓↓↓ 其余逻辑保持不变
WORKDIR=/data/users/kxia/assembly_annotation_course
# HiFi reads：用课程数据在项目根目录的符号链接（你之前有 Pa-1 链接）
READS=$WORKDIR/Pa-1/*.fastq.gz
# 输出放到 evaluations/merqury 下以和其它评估一致
OUTDIR=$WORKDIR/evaluations/merqury
CONTAINER_PATH="/containers/apptainer/merqury_1.3.sif"

mkdir -p $OUTDIR

# 三个 genome assemblies 的实际位置（与你的 config 一致）
FLYE=$WORKDIR/assemblies/flye/assembly.fasta
HIFIASM=$WORKDIR/assemblies/hifiasm/asm.bp.p_ctg.fa
LJA=$WORKDIR/assemblies/lja/assembly.fasta

# Path inside container
export MERQURY="/usr/local/share/merqury"

# Building meryl DB from HiFi reads
if [ ! -d "$OUTDIR/hifi.meryl" ]; then
  echo "Building meryl DB from reads..."
  apptainer exec --bind /data "$CONTAINER_PATH" \
    meryl count k=21 output "$OUTDIR/hifi.meryl" $READS
else
  echo "Using existing meryl DB: $OUTDIR/hifi.meryl"
fi

# Running Merqury for each assembly
for ASM in flye hifiasm lja; do
    echo "Running Merqury for $ASM..."
    mkdir -p "$OUTDIR/$ASM"
    cd "$OUTDIR/$ASM"

    if [ "$ASM" == "flye" ]; then
        ASMFILE="$FLYE"
    elif [ "$ASM" == "hifiasm" ]; then
        ASMFILE="$HIFIASM"
    elif [ "$ASM" == "lja" ]; then
        ASMFILE="$LJA"
    fi

    apptainer exec --bind /data "$CONTAINER_PATH" \
      $MERQURY/merqury.sh "$OUTDIR/hifi.meryl" "$ASMFILE" "$ASM"
done