#!/usr/bin/env bash
#SBATCH --job-name=mummer_all
#SBATCH --partition=pibu_el8
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=06:00:00
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err

set -euo pipefail

# -------------------------------
# Load project config and prepare
# -------------------------------
source scripts/05_01_config.sh
mkdir -p "$EVAL_DIR/mummer" "$ROOT/evaluations/logs"

# -------------------------------
# Detect container runtime
# -------------------------------
CONTAINER=$(command -v apptainer || command -v singularity || true)
if [[ -z "$CONTAINER" ]]; then
  echo "[ERROR] Neither apptainer nor singularity found in PATH. Try: module load Apptainer"
  exit 2
fi

# -------------------------------
# Resolve reference FASTA (auto-fallback if missing)
# -------------------------------
REF_FA="${REF_FASTA:-}"
if [[ ! -s "$REF_FA" ]]; then
  echo "[WARN] REF_FASTA '$REF_FA' not found. Auto-searching in $REF_DIR ..."
  mapfile -t CAND_FA < <(find "$REF_DIR" -maxdepth 3 -type f \
    \( -iname "*TAIR*dna*.fa*" -o -iname "*TAIR*.fa*" -o -iname "*.fna" -o -iname "*.fasta" \) \
    | sort)
  if [[ ${#CAND_FA[@]} -gt 0 ]]; then
    REF_FA="${CAND_FA[0]}"
    echo "[INFO] Using detected reference FASTA: $REF_FA"
  else
    echo "[ERROR] No reference FASTA found under $REF_DIR. Will skip 'vs reference' plots."
    REF_FA=""
  fi
fi

# -------------------------------
# Gather assemblies (Flye / Hifiasm / LJA)
# -------------------------------
mapfile -t GENOME_FASTA < <(find "$ASM_DIR" -maxdepth 2 -type f \
  \( -iname "*flye*.fa*" -o -iname "*hifiasm*.fa*" -o -iname "*lja*.fa*" \
     -o -iname "assembly*.fa*" -o -iname "*.fasta" \) | sort)

if [[ ${#GENOME_FASTA[@]} -eq 0 ]]; then
  echo "[ERROR] No genome assemblies found under: $ASM_DIR"
  exit 2
fi

OUT="$EVAL_DIR/mummer"
TS=$(date +%Y%m%d_%H%M%S)

# -------------------------------
# Helper: run nucmer + mummerplot
# -------------------------------
run_mummerplot() {
  local ref="$1" qry="$2" prefix="$3"
  echo "[RUN] nucmer: ref=$(basename "$ref")  qry=$(basename "$qry")  -> $prefix"
  "$CONTAINER" exec --bind "$ROOT" "$SIF_MUMMER" bash -lc "
    set -euo pipefail
    nucmer --prefix '$prefix' --breaklen 1000 --mincluster 1000 '$ref' '$qry'
    mummerplot --filter --fat --large --layout -t png -R '$ref' -Q '$qry' '${prefix}.delta' -p '$prefix'
  "
}

# -------------------------------
# 1) Compare each assembly against reference (if available)
# -------------------------------
if [[ -n "$REF_FA" ]]; then
  for fa in "${GENOME_FASTA[@]}"; do
    name=$(basename "${fa%.*}")
    pre="$OUT/${name}_vs_ref_${TS}"
    run_mummerplot "$REF_FA" "$fa" "$pre"
  done
else
  echo "[WARN] Skipped 'vs reference' comparisons (no REF FASTA)."
fi

# -------------------------------
# 2) Pairwise comparisons among assemblies
# -------------------------------
for i in "${!GENOME_FASTA[@]}"; do
  for j in $(seq $((i+1)) $(( ${#GENOME_FASTA[@]}-1 )) ); do
    fa1="${GENOME_FASTA[$i]}"; fa2="${GENOME_FASTA[$j]}"
    n1=$(basename "${fa1%.*}"); n2=$(basename "${fa2%.*}")
    pre="$OUT/${n1}_vs_${n2}_${TS}"
    run_mummerplot "$fa1" "$fa2" "$pre"
  done
done

echo "[DONE] MUMmer finished. Dotplots saved in: $OUT"