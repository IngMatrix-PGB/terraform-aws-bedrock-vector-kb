output "knowledge_base_ids" {
  description = "Bedrock Knowledge Base IDs by key."
  value       = { for k, v in awscc_bedrock_knowledge_base.this : k => v.id }
}

output "knowledge_base_arns" {
  description = "Bedrock Knowledge Base ARNs by key (when available in awscc)."
  value       = { for k, v in awscc_bedrock_knowledge_base.this : k => try(v.arn, null) }
}

output "s3vectors_index_arns" {
  description = "Resolved S3 Vectors index ARNs by key."
  value       = local.index_arn_by_kb
}

output "iam_role_arns" {
  description = "IAM Role ARNs used by each KB."
  value       = { for k, v in aws_iam_role.bedrock_kb : k => v.arn }
}

output "ingestion_policy_documents" {
  description = "IAM policy documents (JSON), keyed by kbs entry, granting the minimal permissions (bedrock:StartIngestionJob, GetIngestionJob, ListIngestionJobs) an external actor needs to manage ingestion for that KB, scoped to its ARN. Only present for kbs entries with expose_ingestion_policy = true; this module does not create or attach any IAM resource from this document itself - attach it (as a managed or inline policy) to whatever principal is responsible for triggering and monitoring ingestion. See the README's \"Bedrock / Ingestion Boundary\" section."
  value       = local.ingestion_policy_documents
}
