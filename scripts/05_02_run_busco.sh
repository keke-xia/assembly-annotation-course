#!/usr/bin/env bash
#SBATCH --job-name=busco_all
#SBATCH --partition=phighmem
#SBATCH --cpus-per-task=2                 # fewer threads -> lower peak RAM
#SBATCH --mem=128G                        # use highmem node
#SBATCH --time=2-00:00:00                 # 2 days
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err

set -euo pipefail

# Load config
source scripts/05_01_config.sh

# Threads and scratch
THREADS="${SLURM_CPUS_PER_TASK:-2}"
SCRATCH="/scratch/${USER}/${SLURM_JOB_ID:-busco.$$}"
mkdir -p "$SCRATCH"
echo "[INFO] Using scratch: $SCRATCH"

# Container runtime
CONTAINER=$(command -v apptainer || command -v singularity || true)
[[ -z "$CONTAINER" ]] && { echo "[ERROR] apptainer/singularity not found"; exit 2; }

# Lineage availability
LINEAGE_DIR="$BUSCO_DL/lineages/$BUSCO_LINEAGE"
if [[ -s "$LINEAGE_DIR/dataset.cfg" ]]; then
  RUN_OFFLINE=1; echo "[INFO] OFFLINE lineage: $LINEAGE_DIR"
else
  RUN_OFFLINE=0; echo "[WARN] Lineage missing; will attempt ONLINE (may fail)."
fi

# Find assemblies
mapfile -t GENOME_FASTA < <(find "$ASM_DIR" -maxdepth 2 -type f \
  \( -iname "*flye*.fa*" -o -iname "*hifiasm*.fa*" -o -iname "*lja*.fa*" -o -iname "assembly*.fa*" -o -iname "*.fasta" \) | sort)
TRINITY_FASTA="$(find "$ASM_DIR" -maxdepth 2 -type f -iname "Trinity*.fasta" -o -iname "trinity*.fasta" | head -n1 || true)"
echo "[INFO] Genomes: ${#GENOME_FASTA[@]}  Transcriptome: ${TRINITY_FASTA:-none}"

busco_run() {
  local mode="$1" in_fa="$2" name="$3" outdir_base="$4"
  local ts outdir outname rc
  ts=$(date +%Y%m%d_%H%M%S)
  outdir="${outdir_base}_${ts}"
  outname="${name}_${ts}"
  mkdir -p "$outdir"

  echo "[RUN] BUSCO $mode: $name  -> $outdir  (threads=$THREADS)"

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
      --in "$in_fa" --out "$outname" --out_path "$outdir" \
      -f
  else
    set +e
    "${EXEC_BASE[@]}" busco --mode "$mode" \
      --lineage "$BUSCO_LINEAGE" --download_path "$BUSCO_DL" \
      --cpu "$THREADS" \
      --in "$in_fa" --out "$outname" --out_path "$outdir" \
      -f
    rc=$?; set -e
    [[ $rc -ne 0 || ! -s "$LINEAGE_DIR/dataset.cfg" ]] && { echo "[ERROR] Online BUSCO failed and lineage missing"; exit 2; }
  fi
}

# Genomes (sequential)
for fa in "${GENOME_FASTA[@]}"; do
  name=$(basename "${fa%.*}")
  busco_run "genome" "$fa" "$name" "$EVAL_DIR/busco/${name}"
done

# Transcriptome (optional)
if [[ -n "${TRINITY_FASTA:-}" ]]; then
  name=$(basename "${TRINITY_FASTA%.*}")
  busco_run "transcriptome" "$TRINITY_FASTA" "$name" "$EVAL_DIR/busco/${name}"
fi

echo "[DONE] BUSCO finished."
rm -rf "$SCRATCH" || true