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
[[ -z "$CONTAINER" ]] && { echo "[ERROR] Neither apptainer nor singularity found in PATH. Try: module load Apptainer"; exit 2; }

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
    echo "[WARN] No reference FASTA found under $REF_DIR. Will skip 'vs reference' plots."
    REF_FA=""
  fi
fi

# -------------------------------
# Assemblies from config
# -------------------------------
# 方式 A（推荐，算术判断）
if (( ${#ASSEMBLIES[@]} == 0 )); then
  echo "[ERROR] No assemblies defined in ASSEMBLIES array (scripts/05_01_config.sh)."
  exit 2
fi

mk_name() {
  local f="$1" b
  b="$(basename "$f")"
  b="${b%.fa}"; b="${b%.fasta}"; b="${b%.fa.gz}"; b="${b%.fasta.gz}"
  echo "$b"
}
label_for() {
  local f="$1"
  if [[ ${ASM_LABEL["$f"]+_} ]]; then
    echo "${ASM_LABEL["$f"]}"
  else
    mk_name "$f"
  fi
}

ASM_PATHS=()
ASM_LABELS=()
echo "[INFO] Assemblies:"
for fa in "${ASSEMBLIES[@]}"; do
  if [[ -f "$fa" ]]; then
    ASM_PATHS+=( "$fa" )
    ASM_LABELS+=( "$(label_for "$fa")" )
    echo "  - $(label_for "$fa"): $fa"
  else
    echo "  - MISSING: $fa"
  fi
done
[[ ${#ASM_PATHS[@]} -gt 0 ]] || { echo "[ERROR] No existing assemblies found. Abort."; exit 2; }

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
# 1) Each assembly vs reference (if available)
# -------------------------------
if [[ -n "$REF_FA" ]]; then
  for idx in "${!ASM_PATHS[@]}"; do
    fa="${ASM_PATHS[$idx]}"
    lbl="${ASM_LABELS[$idx]}"
    pre="$OUT/${lbl}_vs_ref_${TS}"
    run_mummerplot "$REF_FA" "$fa" "$pre"
  done
else
  echo "[WARN] Skipped 'vs reference' comparisons (no REF FASTA)."
fi

# -------------------------------
# 2) Pairwise comparisons among assemblies
# -------------------------------
for i in "${!ASM_PATHS[@]}"; do
  for j in $(seq $((i+1)) $(( ${#ASM_PATHS[@]}-1 )) ); do
    fa1="${ASM_PATHS[$i]}"; fa2="${ASM_PATHS[$j]}"
    l1="${ASM_LABELS[$i]}"; l2="${ASM_LABELS[$j]}"
    pre="$OUT/${l1}_vs_${l2}_${TS}"
    run_mummerplot "$fa1" "$fa2" "$pre"
  done
done

echo "[DONE] MUMmer finished. Dotplots saved in: $OUT"