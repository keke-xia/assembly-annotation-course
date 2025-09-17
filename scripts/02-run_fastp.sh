#!/usr/bin/env bash
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --job-name=fastp
#SBATCH --partition=pibu_el8
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --output=/data/users/kxia/assembly_annotation_course/read_QC/output_fastp_%j.o
#SBATCH --error=/data/users/kxia/assembly_annotation_course/read_QC/error_fastp_%j.e

set -euo pipefail

USER="kxia"
USERDIR="/data/users/${USER}/assembly_annotation_course"
ACCESSION="Pa-1"                     
HIFI_DIR="${USERDIR}/${ACCESSION}"
RNA_DIR="${USERDIR}/RNAseq_Sha"

OUTDIR="${USERDIR}/read_QC/fastp"

mkdir -p "${OUTDIR}"


HIFI_READ="$(ls ${HIFI_DIR}/*.fastq.gz 2>/dev/null | head -n1)"
R1="$(ls ${RNA_DIR}/*_1.fastq.gz 2>/dev/null | head -n1)"
R2="${R1/_1.fastq.gz/_2.fastq.gz}"

#look for datas
if [[ -z "${HIFI_READ}" ]]; then
  echo "[ERROR] can't find PacBio HiFi fastq.gz in : ${HIFI_DIR}"
  exit 1
fi

if [[ -z "${R1}" || ! -f "${R2}" ]]; then
  echo "[ERROR] can't find RNA-seq file in : ${RNA_DIR}"
  exit 1
fi

echo "[INFO] PacBio HiFi: ${HIFI_READ}"
echo "[INFO] RNA-seq R1:  ${R1}"
echo "[INFO] RNA-seq R2:  ${R2}"


#fastp module 

module purge || true
module load fastp/0.23.4 || module load fastp || {
  echo "[ERROR] fastp not found x"
  exit 1
}


#RNA-seq trimmed/filtered
#parameters
#  -q 20         : 质量阈值 Q20
#  -u 30         : 允许每条 read 最多 30% 低质碱基
#  -n 5          : 允许 N 的数量
#  -l 36         : 最短保留长度 36bp
#  --detect_adapter_for_pe : 自动检测接头
#  --thread 4    : 线程
RNA_PREFIX="${OUTDIR}/$(basename "${R1/_1.fastq.gz/}")"
fastp \
  -i "${R1}" -I "${R2}" \
  -o "${RNA_PREFIX}_trimmed_1.fastq.gz" \
  -O "${RNA_PREFIX}_trimmed_2.fastq.gz" \
  -q 20 -u 30 -n 5 -l 36 \
  --detect_adapter_for_pe \
  --thread 4 \
  --json "${RNA_PREFIX}_fastp.json" \
  --html "${RNA_PREFIX}_fastp.html"

echo "[INFO] RNA-seq fastp 完成。报告:"
echo "  ${RNA_PREFIX}_fastp.json"
echo "  ${RNA_PREFIX}_fastp.html"


# Run it also on the PacBio Hifi data without filtering to get the total number of bases

PB_PREFIX="${OUTDIR}/$(basename "${HIFI_READ/.fastq.gz/}")"
# no filtering
fastp \
  -i "${HIFI_READ}" \
  -A -Q -L \
  --thread 4 \
  --json "${PB_PREFIX}_fastp.json" \
  --html "${PB_PREFIX}_fastp.html" \
  --stdout > /dev/null

echo "[INFO] PacBio fastp completed. report:"
echo "  ${PB_PREFIX}_fastp.json"
echo "  ${PB_PREFIX}_fastp.html"

echo "[DONE] out put directory: ${OUTDIR}"