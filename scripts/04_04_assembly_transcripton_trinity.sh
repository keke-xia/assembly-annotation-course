#!/usr/bin/env bash
#SBATCH --job-name=trinity_denovo
#SBATCH --partition=pibu_el8
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/%u/assembly_annotation_course/assemblies/trinity/logs/%x-%j.out
#SBATCH --error=/data/users/%u/assembly_annotation_course/assemblies/trinity/logs/%x-%j.err
set -euo pipefail

module purge
module load Trinity

BASE=/data/users/${USER}/assembly_annotation_course
RNA_DIR=${RNA_DIR:-$BASE/RNAseq_Sha}
OUTDIR=$BASE/assemblies/trinity
LOGDIR=$OUTDIR/logs
mkdir -p "$OUTDIR" "$LOGDIR"

# Collect paired-end FASTQ files: *_1.* and *_2.*
mapfile -t LEFTS  < <(find -L "$RNA_DIR" -maxdepth 1 -type f \( -name "*_1.fastq.gz" -o -name "*_1.fq.gz" -o -name "*_1.fastq" -o -name "*_1.fq" \) | sort)
mapfile -t RIGHTS < <(find -L "$RNA_DIR" -maxdepth 1 -type f \( -name "*_2.fastq.gz" -o -name "*_2.fq.gz" -o -name "*_2.fastq" -o -name "*_2.fq" \) | sort)

[[ ${#LEFTS[@]} -gt 0 && ${#LEFTS[@]} -eq ${#RIGHTS[@]} ]] || {
  echo "[ERROR] Paired FASTQ not found or count mismatch in $RNA_DIR"
  exit 2
}

# Convert to comma-separated lists
LEFT_CSV=$(IFS=, ; echo "${LEFTS[*]}")
RIGHT_CSV=$(IFS=, ; echo "${RIGHTS[*]}")

# Run Trinity
Trinity --seqType fq \
        --left  "$LEFT_CSV" \
        --right "$RIGHT_CSV" \
        --CPU "${SLURM_CPUS_PER_TASK}" \
        --max_memory 60G \
        --output "$OUTDIR" \
        --no_version_check

echo "[DONE] Trinity output: $OUTDIR/Trinity.fasta"