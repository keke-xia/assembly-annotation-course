#!/usr/bin/env bash
#SBATCH --job-name=merqury_all
#SBATCH --partition=pibu_el8
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=12:00:00
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.out
#SBATCH --error=/data/users/kxia/assembly_annotation_course/evaluations/logs/%x-%j.err
#SBATCH --chdir=/data/users/kxia/assembly_annotation_course

set -euo pipefail

# -------------------- load config --------------------
source scripts/05_01_config.sh
mkdir -p "$EVAL_DIR/merqury" "$ROOT/evaluations/logs"

# 若配置里没定义 ASM_LABEL，防止后续取用时报未绑定变量
if ! declare -p ASM_LABEL >/dev/null 2>&1; then
  declare -A ASM_LABEL=()
fi

# threads & scratch
THREADS="${SLURM_CPUS_PER_TASK:-8}"
SCRATCH="/scratch/${USER}/${SLURM_JOB_ID:-merqury.$$}"
mkdir -p "$SCRATCH"
echo "[INFO] Using scratch: $SCRATCH"

# container runtime
CONTAINER=$(command -v apptainer || command -v singularity || true)
[[ -z "$CONTAINER" ]] && { echo "[ERROR] Neither apptainer nor singularity found."; exit 2; }

# merqury install path inside container + output base
export MERQURY="/usr/local/share/merqury"
OUTBASE="$EVAL_DIR/merqury"
mkdir -p "$OUTBASE"

# -----------------------------
# 1) Locate high-accuracy reads
# -----------------------------
collect_reads_from_dir() {
  local dir="$1"
  find "$dir" -type f \
    \( -iname "*.fastq.gz" -o -iname "*.fq.gz" -o -iname "*.fastq" -o -iname "*.fq" \) \
    | sort
}

mapfile -t READS < <(
  if [[ -n "${READS_GLOB:-}" ]]; then
    eval "ls -1 ${READS_GLOB}" 2>/dev/null | sort || true
  elif [[ -n "${READS_DIR:-}" && -d "${READS_DIR:-}" ]]; then
    collect_reads_from_dir "$READS_DIR"
  else
    CANDS=( "$ROOT/reads" "$ROOT/data/reads" "$ROOT/hifi" "$ROOT/illumina" "$ROOT/wgs" "$ROOT/Pa-1" "$ROOT/fastq" )
    tmp_list=()
    for d in "${CANDS[@]}"; do
      [[ -d "$d" ]] || continue
      while IFS= read -r f; do tmp_list+=("$f"); done < <(collect_reads_from_dir "$d")
    done
    if [[ ${#tmp_list[@]} -eq 0 ]]; then
      while IFS= read -r f; do tmp_list+=("$f"); done < <(
        find "$ROOT" \
          -type d \( -path "$ROOT/assemblies" -o -path "$ROOT/evaluations" -o -path "$ROOT/scripts" -o -path "$ROOT/busco_downloads" \) -prune -o \
          -type f \( -iname "*.fastq.gz" -o -iname "*.fq.gz" -o -iname "*.fastq" -o -iname "*.fq" \) -print | sort
      )
    fi
    printf "%s\n" "${tmp_list[@]}"
  fi
)

if ((${#READS[@]}==0)); then
  cat >&2 <<EOF
[ERROR] No reads found.
Tried:
  - READS_GLOB=${READS_GLOB:-<unset>}
  - READS_DIR=${READS_DIR:-<unset>}
  - Auto-discovery in common locations under $ROOT

How to fix:
  Option 1) export READS_DIR="/absolute/path/to/your/reads"
  Option 2) export READS_GLOB="/abs/or/relative/pattern/*.fastq.gz"
Then re-run:  sbatch scripts/05_04_run_merqury.sh
EOF
  exit 2
fi

echo "[INFO] Found ${#READS[@]} reads files. Examples:"
printf "  %s\n" "${READS[@]:0:5}"

# -----------------------------
# 2) Build meryl DB for reads
# -----------------------------
MERDB="$EVAL_DIR/merqury/reads.k$K.meryl"
if [[ ! -d "$MERDB" ]]; then
  echo "[RUN] Building meryl DB for reads (k=$K) -> $MERDB"
  build_args=()
  for f in "${READS[@]}"; do
    if [[ "$f" == *.gz ]]; then
      build_args+=( "<(zcat '$f')" )
    else
      build_args+=( "'$f'" )
    fi
  done
  inputs=$(printf " %s" "${build_args[@]}")

  "$CONTAINER" exec -e \
    --env TMPDIR="$SCRATCH" \
    --bind "$ROOT","$SCRATCH" \
    "$SIF_MERQURY" bash -c "
      set -euo pipefail
      meryl count k=$K threads=$THREADS output '$MERDB' $inputs
    "
else
  echo "[SKIP] Found existing meryl DB: $MERDB"
fi

# -----------------------------
# 3) Evaluate each genome assembly (from config)
# -----------------------------
if ((${#ASSEMBLIES[@]}==0)); then
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

echo "[INFO] Genome assemblies from config:"
for fa in "${ASSEMBLIES[@]}"; do
  if [[ -f "$fa" ]]; then
    echo "  - $(label_for "$fa"): $fa"
  else
    echo "  - MISSING: $fa"
  fi
done

for fa in "${ASSEMBLIES[@]}"; do
  [[ -f "$fa" ]] || continue

  label="$(label_for "$fa")"
  outdir="$OUTBASE/${label}"
  prefix="$outdir/${label}"
  mkdir -p "$outdir"

  echo "[RUN] Merqury on $label  <- $(basename "$fa")"

  # Optional per-assembly meryl (for spectra-cn plots)
  asm_meryl="$outdir/${label}.k$K.meryl"
  if [[ ! -d "$asm_meryl" ]]; then
    "$CONTAINER" exec -e \
      --env TMPDIR="$SCRATCH" \
      --bind "$ROOT","$SCRATCH" \
      "$SIF_MERQURY" \
      meryl count k="$K" threads="$THREADS" output "$asm_meryl" "$fa"
  fi

  # Main run: QV / completeness / spectra-cn
  "$CONTAINER" exec -e \
    --env MERQURY="$MERQURY" \
    --env TMPDIR="$SCRATCH" \
    --bind "$ROOT","$SCRATCH" \
    "$SIF_MERQURY" bash -c "
      set -euo pipefail
      \$MERQURY/merqury.sh '$MERDB' '$fa' '$prefix'
    "
  echo "[OK] Merqury done -> $outdir"
done

echo "[DONE] Merqury finished. Check QV/completeness and spectra-cn plots under $OUTBASE"

# cleanup
rm -rf "$SCRATCH" || true