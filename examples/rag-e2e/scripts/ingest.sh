#!/usr/bin/env bash
# Starts a Bedrock ingestion job for the demo Knowledge Base and waits for
# it to finish. Run from examples/rag-e2e after `terraform apply`.
#
# Needs: aws CLI v2, jq, and a principal allowed by the
# `ingestion_policy_document` output.
set -euo pipefail

cd "$(dirname "$0")/.."

KB_ID=$(terraform output -raw knowledge_base_id)
DS_ID=$(terraform output -raw data_source_id)
POLL_SECONDS=${POLL_SECONDS:-10}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-900}

echo "Starting ingestion: knowledge base ${KB_ID}, data source ${DS_ID}"
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "$KB_ID" \
  --data-source-id "$DS_ID" \
  --query 'ingestionJob.ingestionJobId' --output text)
echo "Ingestion job: ${JOB_ID}"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  job=$(aws bedrock-agent get-ingestion-job \
    --knowledge-base-id "$KB_ID" \
    --data-source-id "$DS_ID" \
    --ingestion-job-id "$JOB_ID" \
    --query 'ingestionJob' --output json)
  status=$(jq -r '.status' <<<"$job")
  echo "  status: ${status}"

  case "$status" in
    COMPLETE)
      jq '.statistics' <<<"$job"
      failed=$(jq -r '.statistics.numberOfDocumentsFailed // 0' <<<"$job")
      if [ "$failed" != "0" ]; then
        echo "Finished with ${failed} failed document(s):" >&2
        jq -r '.failureReasons[]?' <<<"$job" >&2
        exit 1
      fi
      echo "Ingestion complete."
      exit 0
      ;;
    FAILED|STOPPED)
      jq -r '.failureReasons[]?' <<<"$job" >&2
      exit 1
      ;;
  esac

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Timed out after ${TIMEOUT_SECONDS}s (job keeps running in AWS)." >&2
    exit 1
  fi
  sleep "$POLL_SECONDS"
done
