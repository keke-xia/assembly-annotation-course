#!/usr/bin/env bash
#SBATCH --job-name=hifiasm_hifi
#SBATCH --partition=pibu_el8
#SBATCH --time=1-00:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/%u/assembly_annotation_course/assemblies/hifiasm/logs/%x-%j.out
#SBATCH --error=/data/users/%u/assembly_annotation_course/assemblies/hifiasm/logs/%x-%j.err
set -euo pipefail

BASE=/data/users/${USER}/assembly_annotation_course
ACCESSION=${ACCESSION:-Pa-1}
HIFI_DIR=${HIFI_DIR:-$BASE/${ACCESSION}}
OUTDIR=$BASE/assemblies/hifiasm
LOGDIR=$OUTDIR/logs
mkdir -p "$OUTDIR" "$LOGDIR"

# Collect HiFi FASTQ reads
mapfile -t HIFI < <(find -L "$HIFI_DIR" -maxdepth 1 -type f \
  \( -name "*.fastq.gz" -o -name "*.fq.gz" -o -name "*.fastq" -o -name "*.fq" \) | sort)
[[ ${#HIFI[@]} -gt 0 ]] || { echo "[ERROR] No HiFi FASTQ in $HIFI_DIR"; exit 2; }

PREFIX=$OUTDIR/asm
apptainer exec --bind /data /containers/apptainer/hifiasm_0.25.0.sif \
  hifiasm -t "${SLURM_CPUS_PER_TASK}" -o "$PREFIX" "${HIFI[@]}" 2> "$PREFIX.run.log"

# Convert GFA output files to FASTA if they exist
for gfa in "$PREFIX".bp.p_ctg.gfa "$PREFIX".p_ctg.gfa \
           "$PREFIX".bp.hap1.p_ctg.gfa "$PREFIX".bp.hap2.p_ctg.gfa \
           "$PREFIX".a_ctg.gfa; do
  if [[ -s "$gfa" ]]; then
    awk '/^S/{print ">"$2;print $3}' "$gfa" > "${gfa%.gfa}.fa"
    echo "[INFO] GFA -> FASTA: ${gfa%.gfa}.fa"
  fi
done

echo "[DONE] hifiasm output dir: $OUTDIR"