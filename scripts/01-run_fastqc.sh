#!/usr/bin/env bash
#SBATCH --cpus-per-task=1
#SBATCH --mem=40G
#SBATCH --time=01:00:00
#SBATCH --job-name=fastqc
#SBATCH --mail-user=keke.xia@students.unibe.ch
#SBATCH --mail-type=end
#SBATCH --output=/data/users/kxia/assembly_annotation_course/read_QC/output_fastqc_%j.o
#SBATCH --error=/data/users/kxia/assembly_annotation_course/read_QC/error_fastqc_%j.e
#SBATCH --partition=pibu_el8

WORKDIR=/data/users/kxia/assembly_annotation_course


#FastQC
apptainer exec \
--bind $WORKDIR \
/containers/apptainer/fastqc-0.12.1.sif \
fastqc \
--help