#!/usr/bin/env bash
#SBATCH --job-name=quast_all
#SBATCH --partition=pibu_el8
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course

set -euo pipefail

# Load config
source scripts/05_01_config.sh
mkdir -p "$EVAL_DIR/quast" "$ROOT/evaluations/logs"

# Detect container runtime
CONTAINER=$(command -v apptainer || command -v singularity || true)
if [[ -z "$CONTAINER" ]]; then
  echo "[ERROR] Neither apptainer nor singularity found."
  exit 2
fi

# ---- Auto-detect reference FASTA if the configured one is missing ----
REF_FA="${REF_FASTA:-}"
if [[ ! -s "$REF_FA" ]]; then
  echo "[WARN] REF_FASTA '$REF_FA' not found. Auto-searching in $REF_DIR ..."
  # common Arabidopsis naming patterns
  mapfile -t CAND_FA < <(find "$REF_DIR" -maxdepth 2 -type f \
    \( -iname "*TAIR*dna*.fa*" -o -iname "*TAIR*.fa*" -o -iname "*.fna" -o -iname "*.fasta" \) \
    | sort)
  if [[ ${#CAND_FA[@]} -gt 0 ]]; then
    REF_FA="${CAND_FA[0]}"
    echo "[INFO] Using detected reference FASTA: $REF_FA"
  else
    echo "[ERROR] No reference FASTA found under $REF_DIR. Will run the 'without reference' mode only."
    REF_FA=""
  fi
fi

# ---- Auto-detect annotation (features) if the configured one is missing ----
# We try gff3/gff/gtf, with/without .gz
ANN_FILE="${REF_GFF3:-}"
if [[ ! -s "$ANN_FILE" ]]; then
  echo "[WARN] Annotation file '$ANN_FILE' not found. Auto-searching in $REF_DIR ..."
  mapfile -t CAND_ANN < <(find "$REF_DIR" -maxdepth 2 -type f \
    \( -iname "*.gff3.gz" -o -iname "*.gff3" -o -iname "*.gff.gz" -o -iname "*.gff" -o -iname "*.gtf.gz" -o -iname "*.gtf" \) \
    | sort)
  if [[ ${#CAND_ANN[@]} -gt 0 ]]; then
    ANN_FILE="${CAND_ANN[0]}"
    echo "[INFO] Using detected annotation: $ANN_FILE"
  else
    echo "[WARN] No GFF/GTF annotation found under $REF_DIR. Proceeding WITHOUT --features."
    ANN_FILE=""
  fi
fi

# Find genome assemblies
mapfile -t GENOME_FASTA < <(find "$ASM_DIR" -maxdepth 2 -type f \
  \( -iname "*flye*.fa*" -o -iname "*hifiasm*.fa*" -o -iname "*lja*.fa*" \
     -o -iname "assembly*.fa*" -o -iname "*.fasta" \) | sort)

labels=$(printf "%s\n" "${GENOME_FASTA[@]##*/}" | sed 's/\.[^.]*$//' | paste -sd "," -)

# -------- QUAST without reference --------
OUT1="$EVAL_DIR/quast/no_ref"
mkdir -p "$OUT1"
echo "[RUN] QUAST without reference"
"$CONTAINER" exec --bind "$ROOT" "$SIF_QUAST" \
  quast.py --eukaryote --threads "$THREADS" \
  --labels "$labels" \
  -o "$OUT1" "${GENOME_FASTA[@]}"

# -------- QUAST with reference (only if REF available) --------
if [[ -n "$REF_FA" ]]; then
  OUT2="$EVAL_DIR/quast/with_ref"
  mkdir -p "$OUT2"
  echo "[RUN] QUAST with reference"
  if [[ -n "$ANN_FILE" ]]; then
    # with features
    "$CONTAINER" exec --bind "$ROOT" "$SIF_QUAST" \
      quast.py --eukaryote --threads "$THREADS" \
      --est-ref-size 135000000 \
      -R "$REF_FA" --features "$ANN_FILE" \
      --labels "$labels" \
      -o "$OUT2" "${GENOME_FASTA[@]}"
  else
    # without features (annotation missing)
    "$CONTAINER" exec --bind "$ROOT" "$SIF_QUAST" \
      quast.py --eukaryote --threads "$THREADS" \
      --est-ref-size 135000000 \
      -R "$REF_FA" \
      --labels "$labels" \
      -o "$OUT2" "${GENOME_FASTA[@]}"
  fi
else
  echo "[WARN] Skipped 'with reference' run because no reference FASTA was found."
fi

echo "[DONE] QUAST finished."