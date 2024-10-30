#!/usr/bin/env bash
START=$(date -d "-1 month" +"%Y-%m-01")
END=$(date +"%Y-%m-01")
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=REGION \
  --query "ResultsByTime[].Groups[].[Keys[0], Metrics.UnblendedCost.Amount]" \
  --output text > billing_regions.txt
echo "region, cost" > billing_report_regions.csv
cat billing_report_regions.txt | tr -s '\t' ',' >> billing_report_regions.csv
