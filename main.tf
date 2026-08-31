locals {
  # Only create when enabled, and when we can resolve an index ARN (created or provided).
  requested_kbs = var.enable_kbs ? var.kbs : {}

  create_vectors = {
    for k, v in local.requested_kbs : k => v
    if try(v.create_s3vectors, false) == true
  }

  use_existing_index = {
    for k, v in local.requested_kbs : k => v
    if try(v.create_s3vectors, false) == false && trimspace(try(v.s3vectors_index_arn, "")) != ""
  }
}

# -----------------------------
# S3 Vectors: Vector Bucket + Index
# -----------------------------
resource "aws_s3vectors_vector_bucket" "this" {
  for_each = local.create_vectors

  vector_bucket_name = each.value.s3vectors_bucket_name

  tags = merge(var.tags, {
    Name    = each.value.s3vectors_bucket_name
    Module  = "bedrock-vector-kb"
    Service = "s3vectors"
  })
}

resource "aws_s3vectors_index" "this" {
  for_each = local.create_vectors

  index_name         = each.value.s3vectors_index_name
  vector_bucket_name = each.value.s3vectors_bucket_name
  data_type          = each.value.s3vectors_data_type
  dimension          = each.value.s3vectors_dimension
  distance_metric    = each.value.s3vectors_distance_metric

  tags = merge(var.tags, {
    Name    = each.value.s3vectors_index_name
    Module  = "bedrock-vector-kb"
    Service = "s3vectors"
  })

  depends_on = [aws_s3vectors_vector_bucket.this]
}

locals {
  index_arn_by_kb = merge(
    { for k, v in local.create_vectors : k => aws_s3vectors_index.this[k].index_arn },
    { for k, v in local.use_existing_index : k => v.s3vectors_index_arn }
  )

  enabled_kbs = {
    for k, v in local.requested_kbs : k => v
    if contains(keys(local.index_arn_by_kb), k)
  }

  # Docs bucket security opt-ins: only present when the caller supplied them.
  kbs_with_kms = {
    for k, v in local.enabled_kbs : k => v
    if try(v.kms_key_arn, null) != null
  }

  kbs_with_logging = {
    for k, v in local.enabled_kbs : k => v
    if try(v.logging_target_bucket, null) != null
  }

  kbs_with_ingestion_policy = {
    for k, v in local.enabled_kbs : k => v
    if try(v.expose_ingestion_policy, false) == true
  }
}

# -----------------------------
# S3 bucket for documents (optional create)
# -----------------------------
resource "aws_s3_bucket" "kb_docs" {
  for_each = local.enabled_kbs
  bucket   = each.value.content_bucket

  tags = merge(var.tags, {
    Name    = each.value.content_bucket
    Module  = "bedrock-vector-kb"
    Service = "bedrock-kb-docs"
  })
}

resource "aws_s3_bucket_public_access_block" "kb_docs" {
  for_each = local.enabled_kbs
  bucket   = aws_s3_bucket.kb_docs[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "kb_docs" {
  for_each = local.enabled_kbs
  bucket   = aws_s3_bucket.kb_docs[each.key].id

  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_docs" {
  for_each = local.enabled_kbs
  bucket   = aws_s3_bucket.kb_docs[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = try(each.value.kms_key_arn, null) != null ? "aws:kms" : "AES256"
      kms_master_key_id = try(each.value.kms_key_arn, null)
    }
    bucket_key_enabled = try(each.value.kms_key_arn, null) != null
  }
}

# -----------------------------
# Docs bucket hardening: deny non-TLS access (always enforced, no opt-out)
# -----------------------------
data "aws_iam_policy_document" "kb_docs_tls_only" {
  for_each = local.enabled_kbs

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.kb_docs[each.key].arn,
      "${aws_s3_bucket.kb_docs[each.key].arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "kb_docs_tls_only" {
  for_each = local.enabled_kbs

  bucket = aws_s3_bucket.kb_docs[each.key].id
  policy = data.aws_iam_policy_document.kb_docs_tls_only[each.key].json
}

# -----------------------------
# Docs bucket hardening: lifecycle
#
# The multipart-upload cleanup rule is universal hygiene with no impact on
# any valid object. Noncurrent-version expiration is genuinely destructive
# retention behavior (it permanently deletes old version content), so it
# is only present when the caller opts in via
# noncurrent_version_expiration_days - never a default.
# -----------------------------
resource "aws_s3_bucket_lifecycle_configuration" "kb_docs" {
  for_each = local.enabled_kbs

  bucket = aws_s3_bucket.kb_docs[each.key].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = try(each.value.noncurrent_version_expiration_days, null) != null ? [each.value.noncurrent_version_expiration_days] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
    }
  }
}

# -----------------------------
# Docs bucket hardening: optional access logging (bring your own log bucket)
# -----------------------------
resource "aws_s3_bucket_logging" "kb_docs" {
  for_each = local.kbs_with_logging

  bucket        = aws_s3_bucket.kb_docs[each.key].id
  target_bucket = each.value.logging_target_bucket
  target_prefix = each.value.logging_target_prefix
}

# -----------------------------
# IAM Role + Policies for Bedrock KB
# -----------------------------
data "aws_iam_policy_document" "bedrock_kb_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bedrock_kb" {
  for_each = local.enabled_kbs

  name               = each.value.role_name
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume.json

  tags = merge(var.tags, {
    Name    = each.value.role_name
    Module  = "bedrock-vector-kb"
    Service = "bedrock-kb"
  })
}

resource "aws_iam_policy" "bedrock_invoke_model" {
  for_each = local.enabled_kbs
  name     = "${each.value.role_name}-invoke-model"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "BedrockInvokeModel"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = [each.value.embedding_model_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "invoke_model" {
  for_each   = local.enabled_kbs
  role       = aws_iam_role.bedrock_kb[each.key].name
  policy_arn = aws_iam_policy.bedrock_invoke_model[each.key].arn
}

resource "aws_iam_policy" "kb_s3_read" {
  for_each = local.enabled_kbs
  name     = "${each.value.role_name}-s3-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${each.value.content_bucket}"]
      },
      {
        Sid    = "S3GetObject"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          trimspace(try(each.value.content_prefix, "")) != "" ?
          "arn:aws:s3:::${each.value.content_bucket}/${trim(each.value.content_prefix, "/")}/*" :
          "arn:aws:s3:::${each.value.content_bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  for_each   = local.enabled_kbs
  role       = aws_iam_role.bedrock_kb[each.key].name
  policy_arn = aws_iam_policy.kb_s3_read[each.key].arn
}

resource "aws_iam_policy" "s3vectors" {
  for_each = local.enabled_kbs
  name     = "${each.value.role_name}-s3vectors"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3VectorsPermissions"
      Effect = "Allow"
      Action = [
        "s3vectors:GetIndex",
        "s3vectors:QueryVectors",
        "s3vectors:PutVectors",
        "s3vectors:GetVectors",
        "s3vectors:DeleteVectors"
      ]
      Resource = local.index_arn_by_kb[each.key]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3vectors" {
  for_each   = local.enabled_kbs
  role       = aws_iam_role.bedrock_kb[each.key].name
  policy_arn = aws_iam_policy.s3vectors[each.key].arn
}

# Only created when the caller opts into SSE-KMS via kms_key_arn - the
# Bedrock role needs this to read/write KMS-encrypted docs objects.
resource "aws_iam_policy" "kb_s3_kms" {
  for_each = local.kbs_with_kms
  name     = "${each.value.role_name}-s3-kms"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3DocsKmsAccess"
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      Resource = each.value.kms_key_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_kms" {
  for_each   = local.kbs_with_kms
  role       = aws_iam_role.bedrock_kb[each.key].name
  policy_arn = aws_iam_policy.kb_s3_kms[each.key].arn
}

# Deliberately NOT added to awscc_bedrock_knowledge_base/data_source's
# depends_on below: local.kbs_with_kms only has instances for KBs that
# opted into kms_key_arn, so adding this resource address to a shared
# depends_on list would force every KB (including ones with no KMS key at
# all) to wait on it collectively - an unnecessary cross-KB coupling.
# KMS access is only exercised later, during ingestion, not at KB
# creation time, so there is no correctness reason to order it before KB
# creation the way the other 3 (always-present) policy attachments are.

locals {
  # Only present when the caller opts into chunking via kbs[*].chunking; null
  # (the default) sends no vector_ingestion_configuration argument at all, so
  # AWS applies its own default chunking behavior, unchanged from v0.1.0.
  #
  # NOTE ON REPLACEMENT: per the AWS::Bedrock::DataSource CloudFormation
  # resource schema, ChunkingConfiguration is a createOnlyProperty - changing
  # it (including turning it on/off) forces awscc to replace the data source,
  # not update it in place. See README "Chunking" section.
  chunking_vector_ingestion_configuration_by_kb = {
    for k, v in local.enabled_kbs : k => (
      try(v.chunking, null) == null ? null : {
        chunking_configuration = merge(
          { chunking_strategy = v.chunking.strategy },
          v.chunking.strategy == "FIXED_SIZE" ? {
            fixed_size_chunking_configuration = {
              max_tokens         = v.chunking.fixed_size.max_tokens
              overlap_percentage = v.chunking.fixed_size.overlap_percentage
            }
          } : {},
          v.chunking.strategy == "HIERARCHICAL" ? {
            hierarchical_chunking_configuration = {
              overlap_tokens = v.chunking.hierarchical.overlap_tokens
              level_configurations = [
                for lvl in v.chunking.hierarchical.level_configurations : { max_tokens = lvl.max_tokens }
              ]
            }
          } : {},
          v.chunking.strategy == "SEMANTIC" ? {
            semantic_chunking_configuration = {
              max_tokens                      = v.chunking.semantic.max_tokens
              buffer_size                     = v.chunking.semantic.buffer_size
              breakpoint_percentile_threshold = v.chunking.semantic.breakpoint_percentile_threshold
            }
          } : {}
        )
      }
    )
  }
}

# -----------------------------
# Bedrock Knowledge Base + Data Source (AWSCC)
# -----------------------------
resource "awscc_bedrock_knowledge_base" "this" {
  for_each = local.enabled_kbs

  name        = each.value.kb_name
  description = try(each.value.kb_description, null)
  role_arn    = aws_iam_role.bedrock_kb[each.key].arn

  knowledge_base_configuration = {
    type = "VECTOR"
    vector_knowledge_base_configuration = {
      embedding_model_arn = each.value.embedding_model_arn
    }
  }

  storage_configuration = {
    type = "S3_VECTORS"
    s3_vectors_configuration = {
      index_arn = local.index_arn_by_kb[each.key]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.invoke_model,
    aws_iam_role_policy_attachment.s3_read,
    aws_iam_role_policy_attachment.s3vectors
  ]
}

# Optional, per-KB IAM policy DOCUMENT (JSON) for an external actor to manage
# ingestion jobs - never created or attached by this module. See the README's
# "Bedrock / Ingestion Boundary" section for the full rationale.
#
# Deliberately NOT granted to the Bedrock execution role above
# (aws_iam_role.bedrock_kb): that role is assumed BY the Bedrock service
# itself to do its own internal work during an already-started ingestion job
# (invoke the embedding model, read S3 documents, write to the vector store)
# - it is never the caller of StartIngestionJob/GetIngestionJob/
# ListIngestionJobs. Those APIs are called by whatever EXTERNAL principal
# (CI role, application role, Lambda execution role, human operator role)
# triggers and monitors ingestion, which this module has no way to know or
# own. Granting these actions to the service role would be accepted by IAM
# but would be semantically wrong (a permission that identity never
# exercises) and would not help the actual caller.
#
# Per AWS's own IAM Service Authorization Reference for Amazon Bedrock, all
# three actions support resource-level permissions scoped ONLY to the
# knowledge-base resource type (arn:${Partition}:bedrock:${Region}:
# ${Account}:knowledge-base/${KnowledgeBaseId}) - there is no data-source- or
# ingestion-job-level ARN to scope to instead, so granting these actions for
# a KB with more than one data source authorizes ingestion for any of that
# KB's data sources, not just one. This module currently creates exactly one
# data source per KB, but the IAM scoping limitation is AWS's, not this
# module's, and is documented as such in the README.
locals {
  ingestion_policy_documents = {
    for k, v in local.kbs_with_ingestion_policy : k => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "BedrockIngestionJobManagement"
        Effect = "Allow"
        Action = [
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob",
          "bedrock:ListIngestionJobs",
        ]
        Resource = awscc_bedrock_knowledge_base.this[k].knowledge_base_arn
      }]
    })
  }
}

resource "awscc_bedrock_data_source" "s3" {
  for_each = local.enabled_kbs

  name              = "${each.value.kb_name}-docs"
  knowledge_base_id = awscc_bedrock_knowledge_base.this[each.key].id
  description       = "S3 docs for ${each.value.kb_name}"

  data_source_configuration = {
    type = "S3"
    s3_configuration = merge(
      { bucket_arn = aws_s3_bucket.kb_docs[each.key].arn },
      trimspace(try(each.value.content_prefix, "")) != "" ? {
        inclusion_prefixes = ["${trim(try(each.value.content_prefix, ""), "/")}/"]
      } : {}
    )
  }

  vector_ingestion_configuration = local.chunking_vector_ingestion_configuration_by_kb[each.key]

  depends_on = [
    aws_s3_bucket.kb_docs,
    aws_iam_role_policy_attachment.invoke_model,
    aws_iam_role_policy_attachment.s3_read,
    aws_iam_role_policy_attachment.s3vectors
  ]
}
