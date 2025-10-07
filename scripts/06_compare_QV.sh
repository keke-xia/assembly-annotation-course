# === paths ===
MERQ_DIR="/data/users/kxia/assembly_annotation_course/evaluations/merqury"

FILES=(
  "$MERQ_DIR/flye/flye.assembly.qv"
  "$MERQ_DIR/hifiasm/hifiasm.qv"
  "$MERQ_DIR/lja/lja.assembly.qv"
)
printf "assembly\tagg_QV\tagg_error_rate\tmean_contig_QV\tmin_contig_QV\tn_contigs\tsum_err_kmers\tsum_kmers\n"

for f in "${FILES[@]}"; do
  [ -s "$f" ] || { echo "WARN: missing $f" >&2; continue; }
  asm=$(basename "$(dirname "$f")")   # 目录名作为样本名（flye / hifiasm_primary / lja）

  awk -v asm="$asm" '
    BEGIN{
      sum_err=0; sum_km=0; n_qv=0; sum_qv=0; min_qv=""
    }
    # 期望列为：contig  err_kmers  kmers_in_contig  QV  error_rate
    NF>=5 && $1 !~ /^#/ {
      err=$2; km=$3; qv=$4; er=$5
      # 累加错误kmer与总kmer（inf 行通常 err=0, er=0，对总量是安全的）
      if (err ~ /^[0-9]+$/) sum_err += err
      if (km  ~ /^[0-9]+$/) sum_km  += km

      # 统计 contig QV 的均值/最小值（忽略 inf）
      if (qv != "inf" && qv+0>0){
        n_qv++; sum_qv += qv+0
        if (min_qv=="" || (qv+0) < min_qv){ min_qv = qv+0 }
      }
    }
    END{
      if (sum_km==0){
        agg_er="NA"; agg_qv="NA"
      } else {
        agg_er = sum_err / sum_km
        if (agg_er==0){
          agg_qv="inf"
        } else {
          agg_qv = -10*log(agg_er)/log(10)
        }
      }
      mean_qv = (n_qv>0)? (sum_qv/n_qv) : "NA"
      if (min_qv=="") min_qv="inf"

      # 输出：assembly  聚合QV  聚合错误率  contig均值QV  最差contigQV  contig数  累计错误kmer  累计kmer
      printf("%s\t%s\t%.10g\t%s\t%s\t%d\t%d\t%d\n",
        asm, agg_qv, agg_er, mean_qv, min_qv, n_qv, sum_err, sum_km)
    }
  ' "$f"
done