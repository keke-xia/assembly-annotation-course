#!/usr/bin/env bash
#SBATCH --job-name=busco_all
#SBATCH --partition=phighmem
#SBATCH --cpus-per-task=2
#SBATCH --mem=128G
#SBATCH --time=2-00:00:00
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err

set -euo pipefail

# 1=带时间戳；0=固定名（建议你设 0）
ADD_TS="${ADD_TS:-0}"

source scripts/05_01_config.sh

THREADS="${SLURM_CPUS_PER_TASK:-2}"
SCRATCH="/scratch/${USER}/${SLURM_JOB_ID:-busco.$$}"
mkdir -p "$SCRATCH" "$EVAL_DIR/busco" "$EVAL_DIR/logs"
echo "[INFO] Using scratch: $SCRATCH"

CONTAINER=$(command -v apptainer || command -v singularity || true)
[[ -z "$CONTAINER" ]] && { echo "[ERROR] apptainer/singularity not found"; exit 2; }

LINEAGE_DIR="$BUSCO_DL/lineages/$BUSCO_LINEAGE"
if [[ -s "$LINEAGE_DIR/dataset.cfg" ]]; then
  RUN_OFFLINE=1; echo "[INFO] OFFLINE lineage: $LINEAGE_DIR"
else
  RUN_OFFLINE=0; echo "[WARN] Lineage missing; will attempt ONLINE (may fail)."
fi

# -------- helpers ----------
mk_name() {
  local f="$1" b
  b="$(basename "$f")"
  b="${b%.fa}"; b="${b%.fasta}"; b="${b%.fa.gz}"; b="${b%.fasta.gz}"
  echo "$b" | sed -E 's/[^A-Za-z0-9]+/_/g; s/^_+|_+$//g; s/_+/_/g'
}
label_for() {
  local f="$1"
  # 若配置文件里有 label, 用 label；否则退回清洗过的文件名
  if [[ ${ASM_LABEL["$f"]+_} ]]; then
    echo "${ASM_LABEL["$f"]}"
  else
    mk_name "$f"
  fi
}
# ---------------------------

busco_run() {
  local in_fa="$2" mode="$1" label ts out_dir out_name out_base rc

  # 自动判定模式：Trinity -> transcriptome；否则 genome
  if [[ "$mode" == "auto" ]]; then
    if [[ "$in_fa" =~ [Tt]rinity ]]; then mode="transcriptome"; else mode="genome"; fi
  fi

  label="$(label_for "$in_fa")"

  if [[ "$ADD_TS" == "1" ]]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    out_name="${label}_${ts}"
    out_base="$EVAL_DIR/busco/${label}"
    out_dir="${out_base}/${out_name}"
  else
    out_name="${label}"
    out_dir="$EVAL_DIR/busco/${label}"
  fi
  mkdir -p "$out_dir"

  echo "[RUN] BUSCO $mode: $label  <- $(basename "$in_fa")  -> $out_dir"

  local EXEC_BASE=( "$CONTAINER" exec -e \
    --env TMPDIR="$SCRATCH" \
    --env BUSCO_TMPDIR="$SCRATCH" \
    --env MMSEQS_TMP="$SCRATCH" \
    --env OMP_NUM_THREADS="$THREADS" \
    --env MMSEQS_NUM_THREADS="$THREADS" \
    --env OPENBLAS_NUM_THREADS="$THREADS" \
    --bind "$ROOT","$SCRATCH" \
    "$SIF_BUSCO" )

  if [[ "$RUN_OFFLINE" -eq 1 ]]; then
    "${EXEC_BASE[@]}" busco --mode "$mode" \
      --lineage "$BUSCO_LINEAGE" --download_path "$BUSCO_DL" \
      --offline --cpu "$THREADS" \
      --in "$in_fa" --out "$out_name" --out_path "$out_dir" -f
  else
    set +e
    "${EXEC_BASE[@]}" busco --mode "$mode" \
      --lineage "$BUSCO_LINEAGE" --download_path "$BUSCO_DL" \
      --cpu "$THREADS" \
      --in "$in_fa" --out "$out_name" --out_path "$out_dir" -f
    rc=$?; set -e
    [[ $rc -ne 0 || ! -s "$LINEAGE_DIR/dataset.cfg" ]] && { echo "[ERROR] Online BUSCO failed and lineage missing"; exit 2; }
  fi
}

echo "[INFO] Genome assemblies:"
for f in "${ASSEMBLIES[@]}"; do [[ -f "$f" ]] && echo "  - $(label_for "$f"): $f" || echo "  - MISSING: $f"; done
echo "[INFO] Transcriptomes:"
for f in "${TRANSCRIPTOMES[@]}"; do [[ -f "$f" ]] && echo "  - $(label_for "$f"): $f" || echo "  - MISSING: $f"; done

# 跑 genome
for fa in "${ASSEMBLIES[@]}"; do
  [[ -f "$fa" ]] || { echo "[WARN] Skip missing: $fa"; continue; }
  busco_run "auto" "$fa"
done

# 跑 transcriptome
for fa in "${TRANSCRIPTOMES[@]}"; do
  [[ -f "$fa" ]] || { echo "[WARN] Skip missing: $fa"; continue; }
  busco_run "auto" "$fa"
done

echo "[DONE] BUSCO finished."
rm -rf "$SCRATCH" || true