#!/usr/bin/env bash
#SBATCH --job-name=flye_hifi
#SBATCH --partition=pibu_el8
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/%u/assembly_annotation_course/assemblies/flye/logs/%x-%j.out
#SBATCH --error=/data/users/%u/assembly_annotation_course/assemblies/flye/logs/%x-%j.err
set -euo pipefail

BASE=/data/users/${USER}/assembly_annotation_course
ACCESSION=${ACCESSION:-Pa-1}   #Set your assigned accession if not set in environment
HIFI_DIR=${HIFI_DIR:-$BASE/${ACCESSION}} # HiFi read directory
OUTDIR=$BASE/assemblies/flye
LOGDIR=$OUTDIR/logs
mkdir -p "$OUTDIR" "$LOGDIR"

# Collect HiFi reads (supports fastq/fastq.gz/fasta/fa/fna)
mapfile -t HIFI < <(find -L "$HIFI_DIR" -maxdepth 1 -type f \
  \( -name "*.fastq.gz" -o -name "*.fq.gz" -o -name "*.fastq" -o -name "*.fq" -o -name "*.fa" -o -name "*.fasta" -o -name "*.fna" \) | sort)
[[ ${#HIFI[@]} -gt 0 ]] || { echo "[ERROR] No HiFi files in $HIFI_DIR"; exit 2; }

# Optional: specify genome size if known (e.g., 120m or 2.3g)
GENOME_SIZE=${GENOME_SIZE:-}
GS_ARG=(); [[ -n "$GENOME_SIZE" ]] && GS_ARG=(--genome-size "$GENOME_SIZE")

# Run Flye in HiFi mode
apptainer exec --bind /data /containers/apptainer/flye_2.9.5.sif \
  flye --pacbio-hifi "${HIFI[@]}" \
       --threads "${SLURM_CPUS_PER_TASK}" \
       --out-dir "$OUTDIR" \
       "${GS_ARG[@]}"

echo "[DONE] Flye output: $OUTDIR (assembly.fasta / assembly_info.txt etc.)"