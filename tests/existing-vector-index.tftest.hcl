# Scenario B: create_s3vectors = false, bring-your-own S3 Vectors index
#
# Covers the "existing S3 Vectors store" path: the module must NOT create
# any S3 Vectors bucket/index of its own, and must wire the Knowledge Base
# and IAM policies to the supplied s3vectors_index_arn instead.

mock_provider "aws" {
  override_during = plan

  # See create-vector-index.tftest.hcl for why this mock_data block is
  # required: without it, data.aws_iam_policy_document's mocked .json
  # attribute is a random string, which fails aws_iam_role's own
  # plan-time "must be valid JSON" check.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Action    = "sts:AssumeRole"
          Principal = { Service = "bedrock.amazonaws.com" }
        }]
      })
    }
  }

  # See create-vector-index.tftest.hcl: aws_s3_bucket's computed .arn is
  # not concretized at plan time by override_during = plan alone.
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

mock_provider "awscc" {
  override_during = plan
}

variables {
  enable_kbs = true
  tags       = {}

  kbs = {
    existing_index = {
      kb_name             = "knowledge-base-existing-index"
      role_name           = "bedrock-kb-existing-index-role"
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"

      content_bucket = "matrix-bedrock-documents"
      content_prefix = "existing/"

      create_s3vectors    = false
      s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
    }
  }
}

run "does_not_create_any_s3_vectors_resources" {
  command = plan

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this) == 0
    error_message = "create_s3vectors = false must not plan any S3 Vectors bucket"
  }

  assert {
    condition     = length(aws_s3vectors_index.this) == 0
    error_message = "create_s3vectors = false must not plan any S3 Vectors index (no duplicate/new index)"
  }
}

run "wires_knowledge_base_to_the_supplied_existing_index" {
  command = plan

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Expected exactly one Knowledge Base to be planned"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["existing_index"].storage_configuration.s3_vectors_configuration.index_arn == "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
    error_message = "Knowledge Base must be wired to the supplied existing s3vectors_index_arn, not a newly created index"
  }

  assert {
    condition     = length(awscc_bedrock_data_source.s3) == 1
    error_message = "Expected exactly one S3 data source to be planned"
  }

  assert {
    condition     = awscc_bedrock_data_source.s3["existing_index"].data_source_configuration.s3_configuration.bucket_arn == aws_s3_bucket.kb_docs["existing_index"].arn
    error_message = "Data source must still point at the module-managed documents bucket even when the vector index is external"
  }
}

run "iam_policies_still_resolve_against_the_existing_index" {
  command = plan

  assert {
    condition     = length(aws_iam_role.bedrock_kb) == 1
    error_message = "Expected exactly one IAM role to be planned"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors["existing_index"].policy).Statement[0].Resource == "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
    error_message = "S3 Vectors IAM policy must be scoped to the supplied existing index ARN"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.bedrock_invoke_model["existing_index"].policy).Statement[0].Resource[0] == "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    error_message = "InvokeModel policy must still be scoped to the supplied embedding_model_arn"
  }
}

# NOTE - the "create_s3vectors = false with s3vectors_index_arn
# omitted/blank" case discovered as a crash in PR #3 is now covered in
# tests/invalid-vector-index-input.tftest.hcl (PR #4), which asserts the
# module rejects it with a clear validation error instead of crashing.
