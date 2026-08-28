# Scenario A: create_s3vectors = true
#
# Covers the "new S3 Vectors store" path: the module must create the
# vector bucket + index itself, and wire everything (KB, data source,
# IAM) to that newly created index.
#
# override_during = plan makes mocked computed attributes (e.g.
# aws_s3vectors_index.this[*].index_arn) concrete at plan time instead of
# "(known after apply)", so wiring can be asserted with plain equality.

mock_provider "aws" {
  override_during = plan

  # data.aws_iam_policy_document is a logical (locally-computed) data
  # source, but mock_provider mocks it like any other: without this, its
  # .json attribute becomes a random 8-char string, which fails the real
  # aws_iam_role resource's own plan-time "must be valid JSON" check.
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

  # aws_s3vectors_index/aws_s3_bucket are new-ish resource types whose
  # computed attributes are not concretized at plan time by the generic
  # provider-level override_during = plan alone (verified locally); an
  # explicit per-type default is required for plan-time equality
  # assertions on index_arn/arn to work.
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

  # data_source_configuration.s3_configuration.inclusion_prefixes is
  # optional+computed in the awscc schema; when the module's config omits
  # it (empty content_prefix), override_during = plan alone still leaves
  # it "(known after apply)". An explicit default of an empty list lets
  # the "content_prefix empty" run assert its absence at plan time -
  # explicitly-configured values (the normal case, e.g. "vector-nexus/")
  # still take precedence over this default per Terraform's mocking rules.
  mock_resource "awscc_bedrock_data_source" {
    defaults = {
      data_source_configuration = {
        s3_configuration = {
          inclusion_prefixes = []
        }
      }
    }
  }
}

variables {
  enable_kbs = true

  tags = {
    Project = "matrix-vector-nexus-test"
  }

  kbs = {
    vector_nexus = {
      kb_name             = "knowledge-base-vector-nexus"
      role_name           = "bedrock-kb-vector-nexus-role"
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"

      content_bucket = "matrix-bedrock-documents"
      content_prefix = "vector-nexus/"

      create_s3vectors          = true
      s3vectors_bucket_name     = "matrix-vector-nexus-store"
      s3vectors_index_name      = "matrix-vector-nexus-index"
      s3vectors_dimension       = 1024
      s3vectors_distance_metric = "cosine"
      s3vectors_data_type       = "float32"
    }
  }
}

run "creates_exactly_the_requested_s3_vectors_bucket_and_index" {
  command = plan

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this) == 1
    error_message = "Expected exactly one S3 Vectors bucket to be planned when create_s3vectors = true"
  }

  assert {
    condition     = keys(aws_s3vectors_vector_bucket.this)[0] == "vector_nexus"
    error_message = "The S3 Vectors bucket must be keyed by the kbs map key (vector_nexus)"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["vector_nexus"].vector_bucket_name == "matrix-vector-nexus-store"
    error_message = "S3 Vectors bucket name did not match the supplied s3vectors_bucket_name"
  }

  assert {
    condition     = length(aws_s3vectors_index.this) == 1
    error_message = "Expected exactly one S3 Vectors index to be planned when create_s3vectors = true"
  }

  assert {
    condition     = aws_s3vectors_index.this["vector_nexus"].dimension == 1024
    error_message = "S3 Vectors index dimension did not match the supplied s3vectors_dimension"
  }

  assert {
    condition     = aws_s3vectors_index.this["vector_nexus"].distance_metric == "cosine"
    error_message = "S3 Vectors index distance_metric did not match the supplied s3vectors_distance_metric"
  }

  assert {
    condition     = aws_s3vectors_index.this["vector_nexus"].data_type == "float32"
    error_message = "S3 Vectors index data_type did not match the supplied s3vectors_data_type"
  }
}

run "wires_knowledge_base_and_data_source_to_the_created_index" {
  command = plan

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Expected exactly one Knowledge Base to be planned (no unintended extra KBs)"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["vector_nexus"].name == "knowledge-base-vector-nexus"
    error_message = "Knowledge Base name did not match the supplied kb_name"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["vector_nexus"].storage_configuration.s3_vectors_configuration.index_arn == aws_s3vectors_index.this["vector_nexus"].index_arn
    error_message = "Knowledge Base storage_configuration must reference the index_arn of the S3 Vectors index this module created, not some other value"
  }

  assert {
    condition     = awscc_bedrock_knowledge_base.this["vector_nexus"].knowledge_base_configuration.vector_knowledge_base_configuration.embedding_model_arn == "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    error_message = "embedding_model_arn was not propagated into the Knowledge Base configuration"
  }

  assert {
    condition     = length(awscc_bedrock_data_source.s3) == 1
    error_message = "Expected exactly one S3 data source to be planned"
  }

  assert {
    condition     = awscc_bedrock_data_source.s3["vector_nexus"].name == "knowledge-base-vector-nexus-docs"
    error_message = "Data source name did not follow the expected '<kb_name>-docs' convention"
  }

  assert {
    condition     = awscc_bedrock_data_source.s3["vector_nexus"].data_source_configuration.s3_configuration.bucket_arn == aws_s3_bucket.kb_docs["vector_nexus"].arn
    error_message = "Data source must point at the documents bucket this module created for the same KB key"
  }

  assert {
    condition     = awscc_bedrock_data_source.s3["vector_nexus"].data_source_configuration.s3_configuration.inclusion_prefixes[0] == "vector-nexus/"
    error_message = "content_prefix was not propagated into the data source's inclusion_prefixes"
  }
}

run "wires_iam_role_and_least_privilege_policies" {
  command = plan

  assert {
    condition     = length(aws_iam_role.bedrock_kb) == 1
    error_message = "Expected exactly one IAM role to be planned"
  }

  assert {
    condition     = aws_iam_role.bedrock_kb["vector_nexus"].name == "bedrock-kb-vector-nexus-role"
    error_message = "IAM role name did not match the supplied role_name"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.bedrock_invoke_model["vector_nexus"].policy).Statement[0].Resource[0] == "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    error_message = "InvokeModel policy must be scoped to exactly the supplied embedding_model_arn"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors["vector_nexus"].policy).Statement[0].Resource == aws_s3vectors_index.this["vector_nexus"].index_arn
    error_message = "S3 Vectors policy must be scoped to the index this module created, not a wildcard or another index"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_read["vector_nexus"].policy).Statement[1].Resource[0] == "arn:aws:s3:::matrix-bedrock-documents/vector-nexus/*"
    error_message = "S3 read policy must be scoped to the supplied content_bucket + content_prefix, not the whole bucket"
  }
}

run "content_prefix_empty_grants_whole_bucket_instead_of_a_path" {
  command = plan

  variables {
    kbs = {
      vector_nexus = {
        kb_name             = "knowledge-base-vector-nexus"
        role_name           = "bedrock-kb-vector-nexus-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"

        content_bucket = "matrix-bedrock-documents"
        # content_prefix intentionally omitted (defaults to "")

        create_s3vectors      = true
        s3vectors_bucket_name = "matrix-vector-nexus-store"
        s3vectors_index_name  = "matrix-vector-nexus-index"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_read["vector_nexus"].policy).Statement[1].Resource[0] == "arn:aws:s3:::matrix-bedrock-documents/*"
    error_message = "When content_prefix is empty, the S3 read policy must grant the whole bucket, not a prefixed path"
  }

  assert {
    condition     = length(try(awscc_bedrock_data_source.s3["vector_nexus"].data_source_configuration.s3_configuration.inclusion_prefixes, [])) == 0
    error_message = "When content_prefix is empty, the data source must not set inclusion_prefixes"
  }
}
