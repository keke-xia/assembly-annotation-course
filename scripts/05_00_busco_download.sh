#!/usr/bin/env bash
#SBATCH --job-name=busco_download
#SBATCH --partition=pibu_el8
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=12:00:00
#SBATCH --output=%x_%j.log
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/%u/assembly_annotation_course/assemblies/evaluations/%x-%j.out
#SBATCH --error=/data/users/%u/assembly_annotation_course/assemblies/evaluations/%x-%j.err

set -euo pipefail

ROOT="/data/users/kxia/assembly_annotation_course"
DL="$ROOT/busco_downloads"
SIF="/containers/apptainer/busco_5.7.1.sif"

mkdir -p "$DL"

# Prefer apptainer, fall back to singularity
CONTAINER=$(command -v apptainer || command -v singularity || true)
if [[ -z "$CONTAINER" ]]; then
  echo "[ERROR] Neither apptainer nor singularity is in PATH. Try: module load Apptainer (or Singularity)."
  exit 2
fi

echo "[INFO] Using container runtime: $CONTAINER"
echo "[RUN] Download BUSCO lineage brassicales_odb10 -> $DL"
"$CONTAINER" exec --bind "$ROOT" "$SIF" \
  busco --download brassicales_odb10 --download_path "$DL"

# (可选) 也下这两个，方便 auto-lineage：
# "$CONTAINER" exec --bind "$ROOT" "$SIF" busco --download eukaryota_odb10 --download_path "$DL"
# "$CONTAINER" exec --bind "$ROOT" "$SIF" busco --download embryophyta_odb10 --download_path "$DL"

echo "[OK] Done. Lineage dir should exist at: $DL/lineages/brassicales_odb10"