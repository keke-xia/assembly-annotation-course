#!/usr/bin/env bash
#SBATCH --job-name=quast_per_asm
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

# Read project configuration (paths, assemblies, labels, containers, reference)
source scripts/05_01_config.sh

# Threads: prefer SLURM's cpus-per-task; fallback to THREADS from config
THREADS="${SLURM_CPUS_PER_TASK:-$THREADS}"

# Ensure output directories exist
mkdir -p "$EVAL_DIR/quast" "$EVAL_DIR/logs"

# Detect container runtime (Apptainer/Singularity); try loading module if missing
CONTAINER=$(command -v apptainer || command -v singularity || true)
if [[ -z "${CONTAINER}" ]]; then
  module load Apptainer 2>/dev/null || true
  CONTAINER=$(command -v apptainer || command -v singularity || true)
fi
[[ -n "$CONTAINER" ]] || { echo "[ERROR] Neither apptainer nor singularity found."; exit 2; }

# Bind both the project root and course reference directory (critical for reference access)
BIND_DIRS="${ROOT},/data/courses"

# Reference genome and annotation from config
REF_FA="${REF_FASTA:-}"
ANN_FILE="${REF_GFF3:-}"

# Derive a human-friendly label for an assembly using ASM_LABEL mapping; fallback to basename
get_label() {
  local fa="$1"
  local lbl="${ASM_LABEL[$fa]:-}"
  if [[ -z "$lbl" ]]; then
    lbl="$(basename "$fa")"
    lbl="${lbl%%.*}"
  fi
  echo "$lbl"
}

# One-shot QUAST runner
run_quast() {
  local label="$1"; shift
  local outdir="$1"; shift
  local ref="$1"; shift
  local ann="$1"; shift
  local fasta="$1"; shift

  mkdir -p "$outdir"
  echo "[RUN] ${label} ($(basename "$fasta")) -> $outdir"

  if [[ -n "$ref" ]]; then
    # Reference-based QUAST
    if [[ -n "$ann" ]]; then
      "$CONTAINER" exec --bind "$BIND_DIRS" "$SIF_QUAST" \
        quast.py --eukaryote --large --threads "$THREADS" \
          -R "$ref" --features "$ann" \
          --est-ref-size 135000000 \
          --labels "$label" \
          -o "$outdir" "$fasta"
    else
      "$CONTAINER" exec --bind "$BIND_DIRS" "$SIF_QUAST" \
        quast.py --eukaryote --large --threads "$THREADS" \
          -R "$ref" \
          --est-ref-size 135000000 \
          --labels "$label" \
          -o "$outdir" "$fasta"
    fi
  else
    # Reference-free QUAST
    "$CONTAINER" exec --bind "$BIND_DIRS" "$SIF_QUAST" \
      quast.py --eukaryote --large --threads "$THREADS" \
        --labels "$label" \
        -o "$outdir" "$fasta"
  fi
}

# Iterate over assemblies: run reference-free and reference-based (if reference exists)
for fa in "${ASSEMBLIES[@]}"; do
  if [[ ! -s "$fa" ]]; then
    echo "[WARN] Assembly not found or empty: $fa (skip)"
    continue
  fi
  label="$(get_label "$fa")"

  # Without reference
  run_quast "$label" "$EVAL_DIR/quast/${label}/no_ref" "" "" "$fa"

  # With reference (only if reference fasta exists)
  if [[ -s "$REF_FA" ]]; then
    run_quast "$label" "$EVAL_DIR/quast/${label}/with_ref" "$REF_FA" "$ANN_FILE" "$fa"
  else
    echo "[WARN] No reference FASTA found. Skipping 'with reference' run for $label."
  fi
done

echo "[DONE] All QUAST runs finished."