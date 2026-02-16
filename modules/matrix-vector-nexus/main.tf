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
    Module  = "matrix-vector-nexus"
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
    Module  = "matrix-vector-nexus"
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
}

# -----------------------------
# S3 bucket for documents (optional create)
# -----------------------------
resource "aws_s3_bucket" "kb_docs" {
  for_each = local.enabled_kbs
  bucket   = each.value.content_bucket

  tags = merge(var.tags, {
    Name    = each.value.content_bucket
    Module  = "matrix-vector-nexus"
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
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
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
    Module  = "matrix-vector-nexus"
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

  depends_on = [
    aws_s3_bucket.kb_docs,
    aws_iam_role_policy_attachment.invoke_model,
    aws_iam_role_policy_attachment.s3_read,
    aws_iam_role_policy_attachment.s3vectors
  ]
}
