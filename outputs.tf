output "knowledge_base_ids" {
  description = "Bedrock Knowledge Base IDs by key."
  value       = { for k, v in awscc_bedrock_knowledge_base.this : k => v.id }
}

output "knowledge_base_arns" {
  description = "Bedrock Knowledge Base ARNs by key (when available in awscc)."
  value       = { for k, v in awscc_bedrock_knowledge_base.this : k => try(v.knowledge_base_arn, null) }
}

output "knowledge_base_statuses" {
  description = "Bedrock Knowledge Base status by key (e.g. ACTIVE, CREATING, UPDATING, FAILED, DELETING, DELETE_UNSUCCESSFUL, UPDATE_UNSUCCESSFUL). Reflects the most recently refreshed Terraform state - it is a point-in-time value captured during refresh/plan/apply, not continuous monitoring, polling, or a real-time health check. Re-run terraform plan/apply (or terraform refresh) to get a current value; between runs this output can be stale."
  value       = { for k, v in awscc_bedrock_knowledge_base.this : k => try(v.status, null) }
}

output "data_source_ids" {
  description = "Bedrock data source IDs by kbs key. Combined with knowledge_base_ids, this gives an external actor everything StartIngestionJob's required knowledgeBaseId/dataSourceId path parameters need - this module does not call StartIngestionJob itself (see the README's \"Bedrock / Ingestion Boundary\" section); it only exposes the identifiers that workflow requires."
  value       = { for k, v in awscc_bedrock_data_source.s3 : k => v.data_source_id }
}

output "data_source_statuses" {
  description = "Bedrock data source status by key (AVAILABLE, DELETING, DELETE_UNSUCCESSFUL, CREATING, UPDATING, or FAILED). Reflects the most recently refreshed Terraform state, the same point-in-time caveat as knowledge_base_statuses applies - not continuous monitoring, polling, or a real-time health check."
  value       = { for k, v in awscc_bedrock_data_source.s3 : k => try(v.data_source_status, null) }
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

output "ingestion_log_delivery_source_arns" {
  description = "ARNs of the aws_cloudwatch_log_delivery_source resources created for this KB's APPLICATION_LOGS (ingestion/document-status events), keyed by kbs entry. Only present for entries with ingestion_logging set. This module never creates the delivery destination - see the README's \"Ingestion Log Delivery\" section."
  value       = { for k, v in aws_cloudwatch_log_delivery_source.ingestion : k => v.arn }
}

output "ingestion_log_delivery_arns" {
  description = "ARNs of the aws_cloudwatch_log_delivery resources (the source-to-destination link) created for this KB's ingestion log delivery, keyed by kbs entry. Only present for entries with ingestion_logging set."
  value       = { for k, v in aws_cloudwatch_log_delivery.ingestion : k => v.arn }
}
