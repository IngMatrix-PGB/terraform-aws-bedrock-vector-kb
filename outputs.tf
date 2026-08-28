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
