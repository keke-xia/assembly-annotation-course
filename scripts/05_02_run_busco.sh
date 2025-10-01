#!/usr/bin/env bash
#SBATCH --job-name=busco_all
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
source "/data/users/kxia/assembly_annotation_course/scripts/05_01_config.sh"

# Find genome assemblies
mapfile -t GENOME_FASTA < <(find "$ASM_DIR" -maxdepth 2 -type f \
  \( -iname "*flye*.fa*" -o -iname "*hifiasm*.fa*" -o -iname "*lja*.fa*" \
     -o -iname "assembly*.fa*" -o -iname "*.fasta" \) | sort)

# Find Trinity transcriptome assembly
TRINITY_FASTA="$(find "$ASM_DIR" -maxdepth 2 -type f -iname "Trinity*.fasta" -o -iname "trinity*.fasta" | head -n1 || true)"

echo "[INFO] Found ${#GENOME_FASTA[@]} genome assemblies"
[[ -n "${TRINITY_FASTA:-}" ]] && echo "[INFO] Found transcriptome: $TRINITY_FASTA"

LINEAGE_OPT="--auto-lineage"

# Run BUSCO for genomes
for fa in "${GENOME_FASTA[@]}"; do
  name=$(basename "${fa%.*}")
  outdir="$EVAL_DIR/busco/${name}"
  mkdir -p "$outdir"
  echo "[RUN] BUSCO genome: $name"
  apptainer exec --bind "$ROOT" "$SIF_BUSCO" \
    busco --mode genome $LINEAGE_OPT \
    --cpu "$THREADS" --offline \
    --in "$fa" --out "$name" --out_path "$outdir"
done

# Run BUSCO for transcriptome
if [[ -n "${TRINITY_FASTA:-}" ]]; then
  name=$(basename "${TRINITY_FASTA%.*}")
  outdir="$EVAL_DIR/busco/${name}"
  mkdir -p "$outdir"
  echo "[RUN] BUSCO transcriptome: $name"
  apptainer exec --bind "$ROOT" "$SIF_BUSCO" \
    busco --mode transcriptome $LINEAGE_OPT \
    --cpu "$THREADS" --offline \
    --in "$TRINITY_FASTA" --out "$name" --out_path "$outdir"
fi

echo "[DONE] BUSCO finished. Results in $EVAL_DIR/busco/"