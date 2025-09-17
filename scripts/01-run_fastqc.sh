#!/usr/bin/env bash
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --job-name=fastqc
#SBATCH --partition=pibu_el8
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=end
#SBATCH --output=/data/users/kxia/assembly_annotation_course/read_QC/output_fastqc_%j.o
#SBATCH --error=/data/users/kxia/assembly_annotation_course/read_QC/error_fastqc_%j.e

set -euo pipefail

######### 手动改这里 #########
HIFI_DIR="/data/users/kxia/assembly_annotation_course/Pa-1"
RNA_DIR="/data/users/kxia/assembly_annotation_course/RNAseq_Sha"
OUTDIR="/data/users/kxia/assembly_annotation_course/read_QC/fastqc"
###############################

module load FastQC/0.11.9-Java-11
mkdir -p "$OUTDIR"

echo "[DEBUG] HIFI_DIR -> $HIFI_DIR"
echo "[DEBUG] RNA_DIR  -> $RNA_DIR"
echo "[DEBUG] List HIFI:"
ls -l "$HIFI_DIR" | head || true
echo "[DEBUG] List RNA:"
ls -l "$RNA_DIR" | head || true

# 关键：-L 跟随符号链接
mapfile -t FASTQS < <(find -L "$HIFI_DIR" "$RNA_DIR" -type f \( -name "*.fastq.gz" -o -name "*.fq.gz" \) | sort)

echo "[INFO] Found ${#FASTQS[@]} FASTQ files"
if [[ ${#FASTQS[@]} -eq 0 ]]; then
  echo "[ERROR] No FASTQ files found under:"
  echo "        HIFI_DIR=$HIFI_DIR"
  echo "        RNA_DIR =$RNA_DIR"
  exit 1
fi

fastqc -t "${SLURM_CPUS_PER_TASK:-4}" -o "$OUTDIR" "${FASTQS[@]}"
echo "[DONE] FastQC reports -> $OUTDIR"