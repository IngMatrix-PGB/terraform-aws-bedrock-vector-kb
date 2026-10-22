data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Resolves the inference profile's own ARN and the foundation model ARN in
# every region it routes to - both are needed for least-privilege
# bedrock:InvokeModel (see lambda.tf).
data "aws_bedrock_inference_profile" "generation" {
  inference_profile_id = var.generation_inference_profile_id
}

locals {
  # Account ID suffix keeps the (globally unique) S3 bucket names unique.
  suffix          = data.aws_caller_identity.current.account_id
  content_prefix  = "docs/"
  embedding_model = "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"
}

module "knowledge_base" {
  source = "../.."

  kbs = {
    docs = {
      kb_name             = "${var.name}-kb"
      kb_description      = "RAG demo over the documents in examples/rag-e2e/documents"
      role_name           = "${var.name}-kb-role"
      embedding_model_arn = local.embedding_model

      content_bucket = "${var.name}-docs-${local.suffix}"
      content_prefix = local.content_prefix

      create_s3vectors          = true
      s3vectors_bucket_name     = "${var.name}-vectors-${local.suffix}"
      s3vectors_index_name      = "${var.name}-index"
      s3vectors_dimension       = var.embedding_dimension
      s3vectors_distance_metric = "cosine"

      # Small, overlapping chunks: the sample documents are short runbooks
      # where one rule usually fits in a paragraph.
      chunking = {
        strategy   = "FIXED_SIZE"
        fixed_size = { max_tokens = 300, overlap_percentage = 20 }
      }

      # Outputs the least-privilege policy JSON for whoever runs ingestion
      # (here: you, through scripts/ingest.sh).
      expose_ingestion_policy = true

      # Demo: let `terraform destroy` remove the buckets with their data.
      force_destroy = true
    }
  }
}

# Sample corpus. Terraform only uploads the files; ingestion is started
# separately (scripts/ingest.sh), because Bedrock does not watch the bucket.
resource "aws_s3_object" "documents" {
  for_each = fileset("${path.module}/documents", "*.md")

  bucket       = "${var.name}-docs-${local.suffix}"
  key          = "${local.content_prefix}${each.value}"
  source       = "${path.module}/documents/${each.value}"
  etag         = filemd5("${path.module}/documents/${each.value}")
  content_type = "text/markdown"

  depends_on = [module.knowledge_base]
}
