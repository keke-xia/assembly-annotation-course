#!/usr/bin/env bash
#SBATCH --cpus-per-task=4                    # CPU threads for jellyfish
#SBATCH --mem=96G                            # RAM (needed because we use -s 5G hash)
#SBATCH --time=04:00:00
#SBATCH --job-name=kmer_counting
#SBATCH --partition=pibu_el8
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/kxia/assembly_annotation_course/read_QC/output_kmer_%j.o
#SBATCH --error=/data/users/kxia/assembly_annotation_course/read_QC/error_kmer_%j.e
set -euo pipefail

# ==============================
# User-adjustable settings
# ==============================
User="kxia"
WORKDIR="/data/users/${USER}/assembly_annotation_course"
ACCESSION="Pa-1"                                   # <-- change to your assigned accession (e.g., Pa-1, Abd-0)
IN_DIR="${WORKDIR}/${ACCESSION}"                   # WGS reads directory (do NOT use RNAseq_Sha here)
OUTDIR="${WORKDIR}/read_QC/kmer_counting"
mkdir -p "${OUTDIR}"

#K=21                                               # k-mer length (GenomeScope default)
K=31                                               # k-mer length (recommended for 150bp reads)
THREADS=4                                          # must match --cpus-per-task
HASH=5G                                            # jellyfish hash size; needs >= 40G RAM in the job

# Apptainer image for jellyfish (2.2.6 on your cluster)
JELLY_IMG="/containers/apptainer/jellyfish-2.2.6--0.sif"

# ==============================
# Locate input files
# ==============================
# Collect gzipped FASTQ files from the accession folder
mapfile -t FASTQS < <(ls "${IN_DIR}"/*.fastq.gz 2>/dev/null || true)
if [[ ${#FASTQS[@]} -eq 0 ]]; then
  echo "[ERROR] No FASTQ.GZ files found in ${IN_DIR}"
  echo "       Make sure your symlink exists: ln -s /data/courses/assembly-annotation-course/raw_data/${ACCESSION} ${WORKDIR}/"
  exit 1
fi

echo "[INFO] Found ${#FASTQS[@]} FASTQ files:"
printf '  %s\n' "${FASTQS[@]}"

# ==============================
# Prepare inputs via process substitution
# (jellyfish cannot read .gz; we stream with zcat)
# ==============================
INPUTS=()
for fq in "${FASTQS[@]}"; do
  INPUTS+=( "<(zcat '${fq}')" )
done

STAMP=$(date +%Y%m%d_%H%M%S)
PREFIX="${OUTDIR}/${ACCESSION}.k${K}.${STAMP}"

# ==============================
# Step 1: k-mer counting (canonical)
# ==============================
# -C : canonical k-mers (treat k-mer and reverse-complement as the same)
# -m : k-mer size
# -s : hash size (5G per course hint; request >=40G RAM in SBATCH)
# -t : threads
# -o : output .jf file
echo "[INFO] Running jellyfish count (Apptainer, v2.2.6) ..."
eval apptainer exec --bind "${WORKDIR}" "${JELLY_IMG}" \
  jellyfish count -C -m ${K} -s ${HASH} -t ${THREADS} \
  -o "${PREFIX}.jf" "${INPUTS[@]}"

# ==============================
# Step 2: histogram for GenomeScope2
# ==============================
echo "[INFO] Generating histogram ..."
apptainer exec --bind "${WORKDIR}" "${JELLY_IMG}" \
  jellyfish histo -t ${THREADS} "${PREFIX}.jf" > "${OUTDIR}/reads_k${K}.histo"

echo "[DONE] Upload this file to GenomeScope2: ${OUTDIR}/reads_k${K}.histo"