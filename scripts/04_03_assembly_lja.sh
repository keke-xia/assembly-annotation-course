#!/usr/bin/env bash
#SBATCH --job-name=lja_hifi
#SBATCH --partition=pibu_el8
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/%u/assembly_annotation_course/assemblies/lja/logs/%x-%j.out
#SBATCH --error=/data/users/%u/assembly_annotation_course/assemblies/lja/logs/%x-%j.err
set -euo pipefail

BASE=/data/users/${USER}/assembly_annotation_course
ACCESSION=${ACCESSION:-Pa-1}
HIFI_DIR=${HIFI_DIR:-$BASE/${ACCESSION}}
OUTDIR=$BASE/assemblies/lja
LOGDIR=$OUTDIR/logs
mkdir -p "$OUTDIR" "$LOGDIR"

# Collect HiFi reads (supports FASTA/FASTQ, compressed or uncompressed)
mapfile -t READS < <(find -L "$HIFI_DIR" -maxdepth 1 -type f \
  \( -name "*.fastq.gz" -o -name "*.fq.gz" -o -name "*.fastq" -o -name "*.fq" -o -name "*.fa" -o -name "*.fasta" \) | sort)
[[ ${#READS[@]} -gt 0 ]] || { echo "[ERROR] No HiFi files in $HIFI_DIR"; exit 2; }

ARGS=()
for f in "${READS[@]}"; do ARGS+=(--reads "$f"); done

# Run LJA
apptainer exec --bind /data /containers/apptainer/lja-0.2.sif \
  lja -o "$OUTDIR" -t "${SLURM_CPUS_PER_TASK}" "${ARGS[@]}"

echo "[DONE] LJA output dir: $OUTDIR"