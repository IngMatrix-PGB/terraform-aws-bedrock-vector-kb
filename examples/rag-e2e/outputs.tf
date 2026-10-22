output "query_url" {
  description = "Function URL (AWS_IAM auth). Call it with scripts/ask.py."
  value       = aws_lambda_function_url.query.function_url
}

output "query_caller_policy_document" {
  description = "IAM policy JSON to attach to whoever may call query_url."
  value       = data.aws_iam_policy_document.query_caller.json
}

output "knowledge_base_id" {
  description = "Knowledge Base ID (used by scripts/ingest.sh)."
  value       = module.knowledge_base.knowledge_base_ids["docs"]
}

output "data_source_id" {
  description = "Data source ID (used by scripts/ingest.sh)."
  value       = module.knowledge_base.data_source_ids["docs"]
}

output "content_bucket" {
  description = "Bucket holding the source documents."
  value       = module.knowledge_base.content_bucket_arns["docs"]
}

output "ingestion_policy_document" {
  description = "Least-privilege policy JSON for whoever runs scripts/ingest.sh."
  value       = module.knowledge_base.ingestion_policy_documents["docs"]
}

output "query_log_group" {
  description = "CloudWatch log group of the query function."
  value       = aws_cloudwatch_log_group.query.name
}
