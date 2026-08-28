# Optional coverage: multiple kbs map entries, mixing create_s3vectors = true
# and create_s3vectors = false in the same apply, plus the global enable_kbs
# kill switch. All of this is existing behavior (the kbs variable is already
# a map, and enable_kbs already gates local.requested_kbs) - no new features
# were added to make these tests possible.
#
# Note: the current schema only supports a single global enable_kbs toggle.
# There is no per-entry enabled/disabled field on an individual kbs[key]
# object, so that specific optional scenario from the test plan is not
# applicable to this module as it exists today.

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

  # See create-vector-index.tftest.hcl: these computed attributes are not
  # concretized at plan time by override_during = plan alone.
  mock_resource "aws_s3vectors_index" {
    defaults = {
      index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/mock-vector-bucket/index/mock-vector-index"
    }
  }

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
    created_one = {
      kb_name             = "kb-created-one"
      role_name           = "kb-created-one-role"
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
      content_bucket      = "bucket-one"

      create_s3vectors      = true
      s3vectors_bucket_name = "vector-store-one"
      s3vectors_index_name  = "vector-index-one"
    }

    existing_two = {
      kb_name             = "kb-existing-two"
      role_name           = "kb-existing-two-role"
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
      content_bucket      = "bucket-two"

      create_s3vectors    = false
      s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
    }
  }
}

run "each_map_entry_gets_independent_resources_by_key" {
  command = plan

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 2
    error_message = "Both kbs map entries should produce a Knowledge Base regardless of their create_s3vectors value"
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this) == 1
    error_message = "Only the entry with create_s3vectors = true should get a new S3 Vectors bucket"
  }

  assert {
    condition     = keys(aws_s3vectors_vector_bucket.this)[0] == "created_one"
    error_message = "The created S3 Vectors bucket must belong to created_one, not existing_two"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["created_one"].storage_configuration.s3_vectors_configuration.index_arn == aws_s3vectors_index.this["created_one"].index_arn
    error_message = "created_one's Knowledge Base must be wired to the index this module created for it"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["existing_two"].storage_configuration.s3_vectors_configuration.index_arn == "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
    error_message = "existing_two's Knowledge Base must be wired to its supplied existing index ARN"
  }

  assert {
    condition     = length(aws_iam_role.bedrock_kb) == 2
    error_message = "Each kbs map entry must get its own independent IAM role"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors["created_one"].policy).Statement[0].Resource != jsondecode(aws_iam_policy.s3vectors["existing_two"].policy).Statement[0].Resource
    error_message = "Each KB's S3 Vectors IAM policy must be scoped to its own index, not shared/cross-wired"
  }
}

run "enable_kbs_false_creates_nothing_regardless_of_map_contents" {
  command = plan

  variables {
    enable_kbs = false
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 0
    error_message = "enable_kbs = false must produce zero Knowledge Bases even though the kbs map is non-empty"
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this) == 0
    error_message = "enable_kbs = false must produce zero S3 Vectors resources"
  }

  assert {
    condition     = length(aws_iam_role.bedrock_kb) == 0
    error_message = "enable_kbs = false must produce zero IAM roles"
  }
}
