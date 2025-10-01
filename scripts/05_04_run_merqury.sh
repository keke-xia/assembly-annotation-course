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

# Load config
source scripts/05_01_config.sh
mkdir -p "$EVAL_DIR/merqury" "$ROOT/evaluations/logs"

# Match BUSCO style: threads & per-job scratch
THREADS="${SLURM_CPUS_PER_TASK:-8}"
SCRATCH="/scratch/${USER}/${SLURM_JOB_ID:-merqury.$$}"
mkdir -p "$SCRATCH"
echo "[INFO] Using scratch: $SCRATCH"

# Detect container runtime
CONTAINER=$(command -v apptainer || command -v singularity || true)
if [[ -z "$CONTAINER" ]]; then
  echo "[ERROR] Neither apptainer nor singularity found."
  exit 2
fi

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

if [[ ${#READS[@]} -eq 0 ]]; then
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

  # Clean env (-e), non-login shell (bash -c), pass TMPDIR and bind SCRATCH
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
# 3) Evaluate each genome assembly
# -----------------------------
mapfile -t GENOME_FASTA < <(find "$ASM_DIR" -maxdepth 2 -type f \
  \( -iname "*flye*.fa*" -o -iname "*hifiasm*.fa*" -o -iname "*lja*.fa*" \
     -o -iname "assembly*.fa*" -o -iname "*.fasta" \) | sort)

export MERQURY="/usr/local/share/merqury"  # inside container
OUTBASE="$EVAL_DIR/merqury"
mkdir -p "$OUTBASE"

for fa in "${GENOME_FASTA[@]}"; do
  name=$(basename "${fa%.*}")
  outdir="$OUTBASE/${name}"
  mkdir -p "$outdir"
  echo "[RUN] Merqury on $name"

  # Optional per-assembly meryl (useful for spectra-cn)
  asm_meryl="$outdir/${name}.k$K.meryl"
  if [[ ! -d "$asm_meryl" ]]; then
    "$CONTAINER" exec -e \
      --env TMPDIR="$SCRATCH" \
      --bind "$ROOT","$SCRATCH" \
      "$SIF_MERQURY" \
      meryl count k="$K" threads="$THREADS" output "$asm_meryl" "$fa"
  fi

  # Run merqury.sh with clean env and explicit vars
  "$CONTAINER" exec -e \
    --env MERQURY="$MERQURY" \
    --env TMPDIR="$SCRATCH" \
    --bind "$ROOT","$SCRATCH" \
    "$SIF_MERQURY" bash -c "
      set -euo pipefail
      \$MERQURY/merqury.sh '$MERDB' '$fa' '$outdir/${name}'
    "
  echo "[OK] Merqury done for $name -> $outdir"
done

echo "[DONE] Merqury finished. Check QV/completeness and spectra-cn plots under $OUTBASE"

# Best-effort cleanup
rm -rf "$SCRATCH" || true